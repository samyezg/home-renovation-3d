# Qingzhuangjia (轻装家) — Home Renovation DIY

Hi, I'm Samye — a Flutter developer. This repository is a **portfolio Dart slice** of a shipped home-renovation planning app (floor plan → 3D preview → checklist / DIY).

## Scope

| Included | Not included |
|:---|:---|
| Flutter / Dart app core (`lib/`, `assets/`, `pubspec.yaml`) | `android/` / `ios/` native projects |
| Floor-plan canvas, recognize flow, renov preview, DIY / checklist | Keystore, store configs, release signing |
| Local JSON configs (city tiers, feature flags, legal stubs) | Hardcoded Vision API keys (user enters keys in-app) |

## Features

- **Floor plan input**: templates, hand-drawn rooms, optional photo → vision recognize (user-provided API)
- **Plan canvas**: rooms, doors/windows, snap / edit tools
- **3D preview**: interactive viewer for the current plan
- **Renov preview (P1)**: photo → optional structure anchors → style → before/after (weak-prompt path; generation model optional)
- **Diagnosis / checklist / DIY catalog**: renovation guidance surfaces
- **City-tier estimates**: cost hints from local config

## Tech stack

- Flutter / Dart
- Optional OpenAI-compatible Vision API (base URL + key + models in settings)
- Local persistence for plans / settings
- JSON assets: city tiers, feature flags, legal summaries

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

- This repo is for **architecture review**, not a one-click store build.
- Vision / generation API keys are entered by the end user and stored locally — **no secrets are hardcoded**.
- Structure understanding for renov is **center-point level** (`cx`/`cy`), not contour polygons.
- Full native packaging and store delivery are provided as paid work.

## License

Copyright (c) 2026 Ye Zhiguo (叶志国). All rights reserved. See `LICENSE`.
