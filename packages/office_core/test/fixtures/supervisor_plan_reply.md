I looked at the repository. The settings screen already has a toggle row widget,
so the work splits cleanly into an implementation task and a verification task.

```json
{
  "tasks": [
    {
      "id": "t1",
      "title": "Add dark mode toggle",
      "assignee": "codex",
      "prompt": "In lib/settings/settings_screen.dart add a 'Dark mode' toggle row below 'Notifications' that writes to SettingsStore.darkMode. Verify with `flutter analyze`.",
      "depends_on": []
    },
    {
      "id": "t2",
      "title": "Widget test for toggle",
      "assignee": "claude",
      "prompt": "Write test/settings/dark_mode_toggle_test.dart covering the new toggle in lib/settings/settings_screen.dart. Run it with --timeout 60s.",
      "depends_on": ["t1"]
    }
  ],
  "merge_instructions": "Run flutter analyze and the new widget test, then check the toggle renders at 360x680."
}
```
