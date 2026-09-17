# Array Builder custom source persistence

Version 0.4 keeps a native source snapshot alongside each array recipe. A runtime
Ruby object reference or model-scoped persistent ID alone cannot recover geometry
after closing the model, purging definitions or copying an array to another model.

## Stored data

| Location | Dictionary | Contents |
| --- | --- | --- |
| Array definition | `Na__ArrayBuilder__Definition` | JSON recipe, definition-local path in mm, source name, scale and archive ID |
| Array definition | `Na__ArrayBuilder__Source` | Native SKP archive JSON under `archive` |
| Model | `Na__ArrayBuilder__Sources` | Matching archive JSON keyed by SHA-256 ID |
| Model | `Na__ArrayBuilder__Model` | Recipe index and last creation settings |
| Array instance | `Na__ArrayBuilder__Instance` | Instance identity; generated children carry `role: unit` |

The archive contains schema version, source definition PID/GUID, Base64-encoded
SKP bytes and their SHA-256 digest. Native SKP preserves definition geometry,
nested groups/components, their transformations, attributes and materials. Picked
outer-instance scale and display name are recorded separately. Existing placement
conventions for mirrored/sheared instances are unchanged.

The array definition carries the snapshot so copies do not depend solely on the
originating model dictionary. There is no snapshot on every repeated unit. Source
PID/GUID matching avoids repeated exports while adjusting spacing or offsets.
Snapshot writes are part of the existing geometry operation, so export failures
abort the array change. Parameter-only changes reuse the existing snapshot.

Exports use SketchUp's documented
[`ComponentDefinition#save_copy`](https://ruby.sketchup.com/Sketchup/ComponentDefinition.html#save_copy-instance_method),
which keeps the source's existing file association. Restore uses
[`DefinitionList#load`](https://ruby.sketchup.com/Sketchup/DefinitionList.html#load-instance_method).
Each temporary directory is scoped to a block and removed afterwards. The SKP
bytes inside the model are the persistent asset; no external source path is needed.

## Restoration and editing

1. Inspect surviving generated units for a native source definition. Accept both
   `Sketchup::Group` and `Sketchup::ComponentInstance`. The old component-only
   search was the reason picked groups failed after reselecting.
2. Restore the recorded name and scale into ObjectRegistry. Selection observers
   stop here: following a selection does not create a model operation.
3. When native units are missing, explicit **Edit selected array** or **Update
   array** verifies the embedded archive, then its model backup. Digest or ID
   mismatches cannot silently import damaged geometry.
4. Import the verified bytes inside a separate recovery operation, then regenerate
   through the normal array operation. Failure leaves a message and allows picking
   a replacement source in the same editor.

Switching to parametric blocks keeps the source record and archive. Returning to
Custom object can recover that source even after the block configuration was
saved and the model reopened. A legacy recipe-bearing array with surviving group
units works immediately; its next update adds the archive. An older array whose
source and units were already deleted before a snapshot existed needs a replacement.

## Combined session behaviour

Create / Edit Array hosts one set of controls. Selection changes rotate the UI
context token so delayed changes cannot reach a different array. New array keeps
the current parameters and source while ignoring the still-selected old array
until selection changes again. A completed array becomes the edit target; switching
to Settings or Gallery retains that target. Preset Editor starts a separate draft.

## Verification limits

The isolated Ruby suite verifies archive transport using native API doubles;
the bytes in that fixture are explicitly a stand-in. The supplied native smoke
script creates a real nested group, archives it, removes source references, loads
the archived SKP, checks nested attributes/materials and rebuilds the array. Run
it in a new empty SketchUp model, then save/reopen and reselect the custom array.
That native smoke script has not been executed by this automation session.
