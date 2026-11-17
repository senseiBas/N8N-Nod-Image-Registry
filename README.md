# Automatische Nod Image Registry

Deze repository bouwt uitsluitend de officiële [Nod](https://github.com/n8n-io/nod)-containerimages en publiceert ze naar GHCR. Geen infrastructuurconfiguratie of deployments.

## Werking

De workflow **Nod image registry** controleert dagelijks om 05:23 UTC de HEAD van de officiële upstream-defaultbranch. Dit is een rolling release van de nieuwste commit die alle imagebuilds doorstaat; desktop-releasetags bepalen de bronversie niet. Alle zes builds gebruiken exact dezelfde volledige upstream-SHA.

Elke image wordt native gebouwd voor `linux/amd64` en `linux/arm64` op GitHub-hosted runners. Bestaande commit/architectuurtags worden hergebruikt: ongewijzigde broncode wordt niet opnieuw gebouwd. Ontbrekende builds na een mislukte run worden bij de volgende run hervat. Buildx gebruikt per image en architectuur een GHCR registrycache (`buildcache-amd64` / `buildcache-arm64`).

Pas wanneer alle zes builds geslaagd zijn, worden de drie multi-architecture commitmanifesten samengesteld en gecontroleerd. Daarna wordt `latest` naar dezelfde manifests gepromoveerd en worden de digests gecontroleerd. Volledige SHA-tags en SHA-architectuurtags worden door deze pipeline nooit overschreven. GHCR dwingt deze onveranderlijkheid niet af voor andere schrijvers.

| Image | Officiële Dockerfile | Buildcontext |
| --- | --- | --- |
| `ghcr.io/senseibas/nod-server` | `deployment/self-host/Dockerfile` | Upstream-repositoryroot |
| `ghcr.io/senseibas/nod-browser` | `Dockerfile.browser` | Upstream-repositoryroot |
| `ghcr.io/senseibas/nod-workspace` | `Dockerfile.workspace` | Upstream-repositoryroot |

De paden en architecturen zijn gecontroleerd tegen upstream-commit `cc81434d87b2ad15f7c2d0934c4ac6824c4db0fb`, met name `.github/workflows/self-host-bundle.yml`. Dockerfiles worden rechtstreeks uit de gekozen upstream-commit gebruikt, zonder kopieën of wijzigingen.

## Builddependencies

Upstream pint Node 24.21.0, pnpm 10.34.5 en de base-images met SHA256-digests. Server en browser installeren via Corepack/pnpm de frozen lockfile inclusief patches. Server bouwt de Vite UI; browser bundelt de workers met esbuild en installeert Chromium, Xvfb, ffmpeg en fonts. Workspace gebruikt Rust 1.100.0 voor RTK 0.51.0 (vast bronarchief, checksum en Cargo lockfile), Debian tools waaronder LibreOffice/OCR/media, en Python requirements met verplichte hashes. Voor beide Linux-architecturen gebruikt upstream dezelfde Dockerfiles. Er zijn geen externe applicatiediensten of applicatiecredentials nodig om deze images te bouwen.

Builds hebben netwerktoegang nodig tot Docker Hub, npm, Debian, PyPI, GitHub en crates.io. Runtime-integratietests van Nod met database en applicatiecredentials vallen buiten deze registryrepository; een geslaagde imagebuild is geen volledige applicatie-integratietest.

## Starten en ophalen

De dagelijkse planning, **Actions → Nod image registry → Run workflow** en pushes op `main` die de workflow of het buildscript wijzigen starten de controle. Via CLI:

```sh
gh workflow run registry.yml --repo senseiBas/N8N-Nod-Image-Registry --ref main
gh run list --repo senseiBas/N8N-Nod-Image-Registry --workflow registry.yml
```

Na een succesvolle publicatie:

```sh
docker pull ghcr.io/senseibas/nod-server:latest
docker pull ghcr.io/senseibas/nod-browser:latest
docker pull ghcr.io/senseibas/nod-workspace:latest
```

Voor een vaste versie vervang je `latest` door de volledige upstream-SHA uit de Actions-summary. Docker kiest automatisch de passende architectuur. De summary rapporteert gepubliceerde referenties, upstream-SHA en manifestdigests.

De workflow gebruikt uitsluitend het automatisch verstrekte `GITHUB_TOKEN`: `contents: read` en alleen in build/publicatiejobs `packages: write`. Geen PAT, opgeslagen credentials of handmatige buildgoedkeuring. Actions moet in de repository ingeschakeld zijn. Nieuwe GHCR-packages kunnen standaard privé zijn; anoniem pullen vereist dat de eigenaar de packagevisibility op public zet. Voor bestaande packages moet deze repository schrijfrecht hebben.

## Fouten en herstel

Bekijk de mislukte job onder Actions. Fouten bij authenticatie, netwerk, upstream-dependencies en Dockerbuilds stoppen publicatie. Alleen expliciet ontbrekende manifests leiden tot een build; andere registryfouten worden niet genegeerd. Een mislukte build wijzigt geen enkele `latest`-tag. Geslaagde commitbuilds blijven beschikbaar voor hergebruik bij een retry. Start dezelfde workflow opnieuw of wacht op de volgende dagelijkse run; een kapotte nieuwere upstream-commit vervangt de laatst geslaagde rolling release niet.

GHCR biedt geen transactie over drie packages. Een storing **tijdens de promotie**, nadat alle builds geslaagd zijn, kan tijdelijk verschillende `latest`-versies opleveren. Een retry voltooit de promotie zonder opnieuw te bouwen. Gebruik commit-tags voor een vaste set. Runs worden geserialiseerd en niet halverwege geannuleerd.

Lokale workflowvalidatie: `actionlint .github/workflows/registry.yml` en `bash -n scripts/registry.sh`. Dockerbuilds zelf zijn de vereiste CI-buildvalidatie voor alle zes combinaties; manifestvalidatie en digestvergelijking controleren de publicatie.
