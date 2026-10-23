# LoftLine brand kit

Direction **Cut Path**: a graphite and lime identity built on the router's rapid move. The SVG files in this folder are the source of
truth; everything else (PNGs, `Resources/AppIcon.icns`, the README images) is derived from them.

## Files

| File | Use |
|---|---|
| `wordmark-light.svg`, `wordmark-dark.svg` | "LoftLine" drawn as a single stroke, Regular weight. The `loft` case is aligned to the cap, x-height and baseline lines. |
| `mark-*.svg`, `mark-small-*.svg` | The Rapid mark. Use `mark-small-*` below 48 px: it is drawn again for small sizes, not scaled down. |
| `lockup-h-*.svg`, `lockup-v-*.svg` | Mark and wordmark together, horizontal and vertical. The mark and wordmark are otherwise kept separate. |
| `icon.svg`, `icon-small.svg` | The app icon; `Resources/AppIcon.icns` is built from it. `png/icon-*.png` are the exported sizes. |
| `doc-icon.svg`, `png/doc-icon-512.png` | The icon for `.loftline` documents. |
| `editable/` | Layered SVG and PDF versions for editing in Illustrator, Affinity or Figma. |

## Colour

| Token | Light | Dark |
|---|---|---|
| surface | `#F3F4F6` | `#111317` (graphite) |
| raised | `#FFFFFF` | `#1B1F26` |
| text | `#14171C` | `#ECEEF1` |
| muted | `#566070` | `#9AA3B0` |
| accent (lime) | `#C6EE3A` | `#C6EE3A` |
| accent-text | `#4A6300` | `#D2F25E` |
| hairline | `#D5D9DF` | `#2B313A` |

Contrast (WCAG ratio, computed from the values above):

| Pair | Light | Dark |
|---|---|---|
| text on surface | 16.3 | 16.0 |
| text on raised | 18.0 | 14.2 |
| muted on surface | 5.8 | 7.3 |
| accent-text on surface | 6.2 | 14.7 |
| accent on surface | 1.2 (decorative only) | 13.9 |
| text on accent (button label) | 13.4 | 1.2 (use surface: 13.9) |

## Type

IBM Plex Sans for brand text and IBM Plex Mono for code, G-code and numbers. The app's own interface keeps the system font.

## Clear space and sizes

- Clear space: one quarter of the mark's height on every side.
- Minimum size: the mark 16 px, the lockup 100 px wide. Below 48 px use the `mark-small-*` and `icon-small` drawings.

## Do and do not

- Do use the SVG masters, and the dark surface with lime for large brand moments.
- Do use `accent-text`, not lime, for text on a light surface; lime on light is 1.2:1.
- Do not put the brand colours on the design canvas; the canvas keeps its own neutral palette.
- Do not recolour, stretch, outline, add effects to or re-set the mark or the wordmark in another font.
