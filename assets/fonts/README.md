# EAST. production fonts

EAST. preserves EB Garamond Variable for Latin-script typography and bundles
full-glyph Regular instances of five Noto serif families for Phase 5B.
Corpus-only subsetting is deliberately avoided: Reflections are arbitrary user
text, so every primary family retains its complete upstream cmap and the app/PDF
font plans include every other bundled script as a fallback.

All five new families are redistributed under the SIL Open Font License 1.1.
The exact upstream copyright and license texts are retained at
`licenses/OFL-NotoCJK.txt`, `licenses/OFL-NotoNaskhArabic.txt`, and
`licenses/OFL-NotoSerifThai.txt`. The OFL permits application embedding,
redistribution, modification, and subsetting.

| Locale | Family/output | Official source | Upstream version/commit | Source SHA-256 | Output SHA-256 |
|---|---|---|---|---|---|
| ja | Noto Serif JP / `NotoSerifJP-Regular.ttf` | `google/fonts/ofl/notoserifjp` | noto-cjk `985fa52c81c1d6692ccdd82bc3656e8fb932fd89` | `2fd527ba12b6a44ec30d796d633360da0aeba6c5d4af1304ce12bb4dc15a7dfc` | `83181245ea893229f7f171b9de600d48a58ec607ef46cc3bd11d3d66bdd88fbd` |
| ko | Noto Serif KR / `NotoSerifKR-Regular.ttf` | `google/fonts/ofl/notoserifkr` | noto-cjk `985fa52c81c1d6692ccdd82bc3656e8fb932fd89` | `11f8d5de6f1b79195efba3828aaa2ec95c1178f5ae976fb23c8d53250a9938f3` | `83d1e17d404ffcb6310c89b3def464617cc4831a5fd89af2e58674bd62812b8b` |
| zh-Hant | Noto Serif TC / `NotoSerifTC-Regular.ttf` | `google/fonts/ofl/notoseriftc` | noto-cjk `985fa52c81c1d6692ccdd82bc3656e8fb932fd89` | `0077e18f57c6908f4a000969880940bdb0dad057c0e8d98b49dc364c3d1b09c6` | `703a18dc5b811877ae0bb8aea24a5c61edff3c045fc7abb471c91b54963c1e7f` |
| ar | Noto Naskh Arabic / `NotoNaskhArabic-Regular.ttf` | `google/fonts/ofl/notonaskharabic` | 2.021 / `59f5a3fd985bf24858915c3dddfc51a537640965` | `67b5a525a661b607971fbd3f96a81b89d3a768e74534fca84f18ac97e6fab72f` | `0919edeba540a6b27875d4651f2bf26dcbae00324b4bb034f7a030f7f294d381` |
| th | Noto Serif Thai / `NotoSerifThai-Regular.ttf` | `google/fonts/ofl/notoserifthai` | 2.002 / `f8f3f024703f9d939d02f4e2fe16f1d5a39ca963` | `34a7ad11647c845303aabdde639059806c56b84719e5d2ceb28eb038711bdf53` | `0271d88f4a94c234f47a210f99dc5fb53e2abb50e387d69c20db9c092c5649b1` |

## Reproduction

1. Run `dart run tool/fonts/generate_glyph_inventories.dart`.
2. Install the pinned build-only dependency outside the app package:
   `python3 -m pip install fonttools==4.59.1`.
3. Run `python3 tool/fonts/build_noto_production_fonts.py`.

The build script downloads only the official Google Fonts distributions,
verifies source and output hashes, instantiates weight 400 (and Thai width 100),
retains all glyphs, and checks `GDEF`, `GPOS`, and `GSUB` shaping tables plus
every controlled-copy glyph inventory. Source variable fonts are not shipped.
