# Piste future — ViPER4iOS (projet séparé)

> Note déposée pendant la session TrollBox v2.0 (2026-11-28).
> Le brief complet a été produit comme fichier à télécharger séparé
> et sera utilisé comme kickoff d'un nouveau projet GitHub.

## Résumé de la décision

Port de **ViPERFX / ViPER4Android** sur iOS. Projet **séparé** de TrollBox
(scope UI trop grand, audience plus large que TrollStore-power-users).

## Repos référence

- `github.com/likelikeslike/ViPERFX_RE` — DSP engine C++ reverse-engineered
- `github.com/likelikeslike/ViPER4Android` — UI de référence
- `github.com/likelikeslike/ViPER4Mac` — port Apple Silicon réutilisable

## Scope validé : 4 niveaux

| Niveau | Mécanisme | TrollStore ? | Risque |
|---|---|---|---|
| 1 | Audio Unit Extension v3 | non | nul |
| 2 | Standalone music player | non | nul |
| 3 | Per-app dylib injection (Music, Spotify, YouTube Music…) | oui | modéré |
| 4 | mediaserverd hook (système-wide) | oui | **élevé** (crash = audio mort jusqu'au reboot) |

## Ce que ViPER4iOS réutilisera depuis TrollBox

Les fichiers suivants sont **directement portables** depuis
`TrollBox/ClearShot/` :

- `TFInjector.{h,m}` — orchestration d'injection
- `TFMachO.{h,m}` — Mach-O load command patching
- `TFCodesign.{h,m}` — ad-hoc re-sign via ldid
- `CSProcessUtils.{h,m}` — rootSpawn + sysctl walk
- Pattern `setuid(0); setgid(0);` dans `main.m`
- Structure `TBDiagnosticsManager` pour l'écran Diagnostics
- Pattern `@try/@catch` défensif sur les private APIs

Copier les fichiers tels quels dans le nouveau projet, renommer le
namespace si on veut du propre, mais la logique est debuggée.

## Timing

Attendre que **TrollBox v2.0 soit shippé et stable** (= testé sur device,
build CI vert, diagnostic report confirmant euid=0 et toutes les écritures
root-owned fonctionnelles). Ensuite démarrer ViPER4iOS dans une
conversation séparée avec le brief attaché.

---

*Pour le brief complet : voir `ViPER4iOS-brief.md` (fichier téléchargé
pendant la session TrollBox v2.0 du 2026-11-28).*
