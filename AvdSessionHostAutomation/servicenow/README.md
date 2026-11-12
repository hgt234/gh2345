# ServiceNow integration

ServiceNow supplies request identity only. Azure resource IDs, images, VM sizes,
policies, and service connections stay in the Azure DevOps variable groups.

The integration is optional. Technician-started builds work without any of this
(see the main README). It matters only when ServiceNow queues the pipeline
itself.

## Request contract

[Queue-AvdPipeline.js](Queue-AvdPipeline.js) is the Flow Designer custom Action
script. It queues `pipelines/azure-pipelines-avd-provision.yml` with exactly
these case-sensitive parameter names:

```http
POST https://dev.azure.com/{organization}/{project}/_apis/pipelines/{pipelineId}/runs?api-version=7.1
Content-Type: application/json
Authorization: configured on the REST Message credential
```

```json
{
  "templateParameters": {
    "ritmNumber": "RITM0000001",
    "ritmSysId": "0123456789abcdef0123456789abcdef",
    "requestedHostName": "AVD0000001",
    "requestedForUpn": "user@contoso.com"
  }
}
```

The `workload` parameter is not sent, so the pipeline's default workload is used.
The default is the first entry of the `workload` values list in
`pipelines/azure-pipelines-avd-provision.yml`; keep the production workload
first, or send `workload` from the Action script if more than one exists.

`requestedHostName` is not requester-selected. The Action script derives it as
`AVD` plus the digits of `ritmNumber`, and the pipeline's first stage derives and
checks it again, so a mismatch fails the build before anything is deployed.
Leading zeros are preserved and the Windows name must be 15 characters or fewer.

Supplying `ritmSysId` is what turns on the ServiceNow callbacks. Without it the
pipeline never loads the ServiceNow variable group.

## Fields and statuses

Create or map these `sc_req_item` fields:

| Field | Purpose |
|---|---|
| `u_avd_build_status` | `Queued`, `In Progress`, `Ready`, `Failed`, or `Timed Out` |
| `u_avd_hostname` | Derived hostname |
| `work_notes` | Pipeline progress and failure detail |

ServiceNow sets `Queued` after HTTP 200 or 201 from the Runs API. The pipeline
writes `In Progress`, `Ready`, or `Failed`. The `Timed Out` value is reserved for
a ServiceNow-side timer that fires only if no terminal callback arrives. A
timeout never deletes a VM.

## Authentication

- **ServiceNow to Azure DevOps (queueing):** a short-lived PAT with only
  **Build: Read & execute**, stored in a ServiceNow Basic Auth credential with a
  non-empty username. The PAT owner must hold `Queue builds` on this pipeline
  only; PAT scope alone is not a pipeline boundary. Never put the PAT in a
  script, catalog variable, request body, or work note.
- **Azure DevOps to ServiceNow (callbacks):** OAuth client credentials with an
  auth scope limited to `PATCH /api/now/table/sc_req_item/{sys_id}`. Basic
  authentication remains available as a bootstrap fallback.

## Azure DevOps variables

Variable group `avd-prod-servicenow` (template:
`config/avd-prod-servicenow.variables.example.yml`):

```text
SN_INSTANCE_URL
SN_CLIENT_ID
SN_CLIENT_SECRET
SN_USERNAME
SN_PASSWORD
SN_STATUS_FIELD
SN_HOSTNAME_FIELD
```

Mark `SN_CLIENT_SECRET` and `SN_PASSWORD` secret. Populate either the OAuth pair
or the Basic pair. The callback script treats unresolved `$(NAME)` macros as
absent.

## Guardrail

Conditional Access is out of scope; do not touch it.
