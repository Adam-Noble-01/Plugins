# Gallery Mode

The Gallery tab: every library profile as a card, found by search, opened by a click or a right-click.

## What It Does

- **Gallery and Index views** of the same cards: thumbnails and titles, or full-width rows with keywords.
- **Search** by short name, full name, category or keyword (keyword matches first).
- **Click a card** to pick the profile and go to Apply Profile.
- **Right-click a card** (v1.6.18) for the profile actions menu: Apply Profile To Selection, Create Profile
  Interactive, Edit Profile Information, Edit Profile Geometry. Each opens its tab with that profile chosen
  and the job started. No menu while a swap is armed.
- **Swap Profile**: with a placed trace selected in the model, the Gallery becomes a replacement picker and
  a card click rebuilds the trace with that profile.

## Files

| File | Purpose |
|------|---------|
| `Na__ProfileTools__Gallery__UiSystem__CardRenderer__.js` | Card HTML, SVG thumbnails, search filter and sort |
| `Na__ProfileTools__Gallery__UiSystem__ContextMenu__.js` | The card right-click menu and its four journeys |
| `Na__ProfileTools__Gallery__UiSystem__MainUiLogic__.js` | Tab mount and unmount, toolbar, grid, card events, swap banner |
| `Na__ProfileTools__Gallery__README__.md` | This file |
