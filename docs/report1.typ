#set page(margin: 1.5cm)
#show link: text.with(fill: blue)

// Display inline code in a small box with light gray backround that retains the correct baseline.
#show raw.where(block: false): box.with(
  fill: luma(240),
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 2pt,
)

// Show the text of a footnote a bit smaller
#show footnote.entry: set text(size: 0.8em)

// Display block code in a larger block with more padding
// include a rounded border around it
// Add `fill` attribute to define background color
#show raw.where(block: true): block.with(
  inset: 6pt,
  radius: 2pt,
  stroke: 1pt + luma(200),
)

#show raw: text.with(size: 0.8em)

#align(center, text(size: 30pt)[Labos CSEL1 - partie 1 - 2026])

#text(size: 17pt)[Groupe: André Costa et Samuel Roland]

Notre fork du repository Git est disponible sur #link("https://github.com/samuelroland/csel-workspace").

Notre fork du repository buildroot est disponible sur #link("https://github.com/AndreCostaaa/buildroot/tree/csel").

#outline(title: "Table des matières")

#pagebreak()

#include "./disclaimer.typ"

#pagebreak()

#include "./env.typ"

#pagebreak()
#include "./modules.typ"

#pagebreak()
#include "./drivers.typ"
