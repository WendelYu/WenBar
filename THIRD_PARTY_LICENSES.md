# Third-Party Licenses & Data Attributions

## 1. 7-Zip (`7zz`)
- **Project**: 7-Zip (https://7-zip.org/)
- **License**: GNU LGPL-2.1 (with the unRAR restriction: the unRAR code may not be used to re-create the RAR compression algorithm).
- **Integration**: `7zz` is bundled inside `WenBar.app/Contents/Resources/bin/7zz` and invoked strictly as an external CLI subprocess by `ArchiveTaskManager`. No 7-Zip source code is statically linked into WenBar's Swift binaries.
- **Source Offer**: Users may obtain the corresponding 7-Zip source code from https://7-zip.org/download.html or Homebrew's `sevenzip` formula.

## 2. Chinese Statutory Holidays Data (`holiday-cn`)
- **Project**: `NateScarlet/holiday-cn` (https://github.com/NateScarlet/holiday-cn)
- **License**: MIT License
- **Usage**: Used as the schema reference and online sync source for Chinese statutory holiday and 调休 schedules, supplemented by bundled offline fallback data.
