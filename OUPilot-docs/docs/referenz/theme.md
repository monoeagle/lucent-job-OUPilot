# Darstellung (Theme)

Menü **_Ansicht** schaltet das Erscheinungsbild **live** um (Muster wie im
*CodeSigningCommander*, `ui/theme-loader.psm1`):

- **Farbschema** — 12 Paletten (`Gray`, `Slate`, `Blue`, `Ocean`, `Teal`, `Mint`,
  `Sage`, `Forest`, `Amber`, `Coral`, `Rose`, `Purple`).
- **Stil** — `Sharp` (scharfe Ecken, kompakt) oder `Soft` (3px-Ecken, luftiger).

Das Theme besteht aus zwei ResourceDictionaries, die app-weit gemergt werden:
`ui/themes/palettes/<farbe>.xaml` (nur Farb-Brushes) zuerst, dann
`ui/themes/<stil>.xaml` (Geometrie + Control-Styles, die die Farben per
`DynamicResource` ziehen). Die Wahl wird sofort in `settings.json` gespeichert
(`UiStyle`, `UiPalette`) und beim nächsten Start übernommen.

Farbwechsel greifen sofort; ein Stilwechsel (Geometrie) zieht vollständig erst
beim nächsten Start durch.
