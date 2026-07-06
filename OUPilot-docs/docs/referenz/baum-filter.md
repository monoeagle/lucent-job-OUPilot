# Baum-Filter

Über dem Baum filtert ein Suchfeld die Struktur **live** nach OU- oder
Gruppennamen (Teiltext, Groß-/Kleinschreibung egal).

- Angezeigt wird ein Knoten, wenn sein Name passt **oder** ein Nachfahre passt —
  die Vorfahren bleiben also sichtbar, damit Treffer erreichbar sind.
- Matcht ein OU-Name selbst, erscheint sein kompletter Teilbaum.
- Bei aktivem Filter werden OU-Knoten automatisch aufgeklappt; die Statuszeile
  nennt die Trefferzahl.
- Der **✕**-Button leert das Feld und stellt den vollen Baum wieder her.

Umgesetzt rebuild-basiert über `_Oup-BuildFilteredItem` / `_Oup-RenderTree`
(`ui/main-window.psm1`).
