# Element Assembly Studio Pro - Error Handling Policy

## Purpose
A single, consistent error handling policy applied across all Ruby modules. Resolves the inconsistencies that crept in over the original Window Configurator Tool's lifetime (mixed `StandardError`, `JSON::ParserError`-only, silent rescues, expression-level `Integer(...) rescue false`).

## Categories

### 1. Expected, recoverable - **narrow rescue**
When a specific class of failure is expected and meaningful at the call site, rescue **only that class**.

```ruby
# GOOD - narrow rescue with explicit fallback
begin
    parsed = JSON.parse(payload)
rescue JSON::ParserError => e
    Na__AssemblyStudio::Na__AppUtils::Na__DebugTools.na_debug_warn("Invalid JSON payload: #{e.message}")
    return nil
end

# BAD - swallows everything
parsed = JSON.parse(payload) rescue nil
```

### 2. Type / cast failures - **explicit narrow rescues**
Replace `Integer(...) rescue false` with the actual classes that `Integer()` raises.

```ruby
# GOOD
def self.na_parse_opening_index_match(entry, opening_index)
    Integer(entry.to_s) == opening_index
rescue ArgumentError, TypeError
    false
end

# BAD - hides programming errors
Integer(entry.to_s) == opening_index rescue false
```

### 3. Unexpected, fatal - **let it raise**
Do not rescue programming errors (NoMethodError, NameError, ArgumentError where it indicates a bug). Let SketchUp's Ruby Console show the backtrace so it surfaces during development.

### 4. Top-of-callback boundary rescues - **broad rescue + log + user-visible status**
At the top of `add_action_callback` blocks and other JS<->Ruby crossings, rescue `StandardError` to prevent dialog locks, log a backtrace via `DebugTools`, and push a user-visible status message via `na_send_status_to_dialog`.

```ruby
dialog.add_action_callback("na_createWindow") do |_, raw_payload|
    begin
        Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks.na_handle_create_window(raw_payload)
    rescue StandardError => e
        Na__AssemblyStudio::Na__AppUtils::Na__DebugTools.na_debug_error("na_createWindow failed: #{e.message}", e)
        Na__AssemblyStudio::Na__AppCore::Na__UiBridge.na_send_status(dialog, 'error', 'Failed to create window. See SketchUp Ruby Console for details.')
    end
end
```

## Forbidden patterns

- `... rescue nil` (silent swallowing).
- `... rescue false` (silent swallowing of all `StandardError`).
- Bare `rescue` without a class (catches `StandardError` but reads as "catch everything").
- `rescue Exception` (catches signals, system exits - never appropriate here).
- Mixing user-visible UI status with diagnostic logging (one is for the user, the other for the dev console).

## Logging targets

- **User-facing message** -> `Na__UiBridge.na_send_status(dialog, type, message)` only.
- **Diagnostic / dev** -> `Na__DebugTools.na_debug_*` only. Never `puts`, `print`, `Sketchup.puts`, or `STDOUT.puts` in module code.

The only `puts` calls allowed in the codebase are in the loader script (`Plugins\Na__ElementAssemblyStudioPro__Loader.rb`) for boot diagnostics that happen before `DebugTools` is available.

## Migration checklist (during the EASP refactor)

- [x] Define this policy file.
- [ ] Replace every `Integer(...) rescue false` with the helper above.
- [ ] Replace every `... rescue nil` with a narrow rescue + sensible default.
- [ ] Replace every silent `rescue StandardError` with a logged version.
- [ ] Replace every raw `puts` outside the loader with `DebugTools` calls.
- [ ] Replace every direct `dialog.execute_script("window.na_status...")` with `Na__UiBridge.na_send_status`.
