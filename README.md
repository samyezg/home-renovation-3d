# Qingzhuangjia (轻装家) — Home Renovation DIY

Hi, I'm Samye — a Flutter developer. This repo shows the core Dart architecture of my shipped home-renovation planning app.

Floor plan → 3D preview → renovation checklist / DIY: photo recognize (optional), hand-drawn canvas, renov style preview.

This repository is a **public source architecture sample** of a shipped app. It is **not** a store-ready clone (native Android/iOS projects are omitted). **All Rights Reserved** — viewing does not grant commercial reuse rights.

## Scope

| | |
|:---|:---|
| **Included** | `lib/` (Dart core), `assets/`, `pubspec.yaml` |
| **Not included** | `android/`, `ios/`, signing materials, store listing configs |
| **Store build** | Not produced from this repo alone (native projects omitted) |
| **API key** | Vision / generation keys entered by the end user in Settings; stored locally; **no hardcoded keys** in the repo |
| **SDK** | See `pubspec.yaml` |

## Features

- **Floor plan input** — templates, hand-drawn rooms, optional photo → vision recognize (user-provided API)
- **Plan canvas** — rooms, doors/windows, snap / edit tools
- **3D preview** — interactive viewer for the current plan
- **Renov preview (P1)** — photo → optional structure anchors → style → before/after (weak-prompt path; generation model optional)
- **Diagnosis / checklist / DIY catalog** — renovation guidance surfaces
- **City-tier estimates** — cost hints from local JSON config

## Tech stack

- Flutter / Dart
- Optional OpenAI-compatible Vision API (base URL + key + models in settings)
- Local persistence for plans / settings
- JSON assets: city tiers, feature flags, legal stubs

## Layout

```text
lib/
├── app.dart / main.dart   # entry
├── core/                  # constants, service locator
├── data/                  # catalogs, templates, renov styles
├── features/              # home, plan, recognize, renov, DIY, checklist, diagnosis, safety, mine
├── models/                # plan / domain models
├── services/              # recognize, renov, diagnosis, analytics stub
├── shell/                 # main navigation shell
├── theme/                 # colors, theme, style mode
├── utils/                 # image contain / orientation helpers
└── widgets/               # ROI editor, before/after slider, anchors, etc.

assets/
├── brand/                 # icons
├── config/                # city tiers, feature flags
└── legal/                 # privacy / permissions stubs
```

## Notes

- Structure understanding for renov is **center-point level** (`cx`/`cy`), not contour polygons.
- Full native packaging and store delivery are provided as paid work.

## License

See [`LICENSE`](./LICENSE) (**All Rights Reserved**).

Copyright (c) 2026 Ye Zhiguo (叶志国). All rights reserved.
