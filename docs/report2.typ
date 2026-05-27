#set page(margin: 1.5cm)
#show link: text.with(fill: blue)
#set par(justify: true)

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

#align(center, text(size: 30pt)[Labos CSEL1 - partie 2 - 2026])

#text(size: 17pt)[Groupe: André Costa et Samuel Roland]

Notre fork du repository Git est disponible sur #link("https://github.com/samuelroland/csel-workspace").

Notre fork du repository buildroot est disponible sur #link("https://github.com/AndreCostaaa/buildroot/tree/csel").

#outline(title: "Table des matières")

#pagebreak()

#include "./system.typ"

#pagebreak()
#include "./procs.typ"

#pagebreak()
#include "./perf.typ"

= Conclusion
Etant fan des modes watch, comprendre plus en détails comment implémenter l'écoute d'événements via `epoll` et voir `inotify` a été intéressant pour Samuel. Pour la partie sur les signaux, la gestion des lectures/écritures qui doivent supporter leur arrêt causé par des interruptions étaient également nouveaux pour Samuel. La gestion des cgroups n'est pas toujours évidente, mais avec l'aide de différents morceaux de la documentation officielle et quelques articles, le sujet est devenu beaucoup accessible et intéressant à explorer en pratique. HTOP s'est avéré d'une grande aide pour comprendre l'effet des cgroups pour les restrictions de CPU. Nous avions déjà vu Perf et d'autres outils de performance durant un cours de HPC en bachelor, la majorité des notions de perf étaient connues mais nous avons découvert quelques options de la TUI `perf report`.
