#set page(margin: 1.5cm)

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


#align(center, text(size: 30pt)[Labos CSEL1 - partie 1])

#text(size: 17pt)[Binôme: André Costa et Samuel Roland]

#outline(title: "Table des matières")

#include "./disclaimer.typ"

// TODO: should we rename this to setup ?
#include "./week1.typ"

#include "./modules.typ"

#include "./drivers.typ"
