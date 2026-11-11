# hush editorial artwork

## Studio lighting

- `src/landing/assets/studio-environment.ktx2.gz` is generated from Three.js's `RoomEnvironment` with its PMREM filter. It contains lighting, not a photograph or generated illustration.
- Rebuild with `node scripts/bake-studio-environment.mjs` from `webapp/`, using the pinned Three.js version. Six half-float reflection levels are stored in KTX2 and gzip-compressed for delivery; each level is area-downsampled by two before packaging.
- Source: [Three.js RoomEnvironment](https://github.com/mrdoob/three.js/blob/r187/examples/jsm/environments/RoomEnvironment.js), MIT. The notice is preserved in `/third-party/three-LICENSE.txt`. The MIT-licensed `ktx-parse` reader's notice is in `/third-party/ktx-parse-LICENSE.txt`.

These are existing public-domain artworks and an openly licensed photograph, not AI-generated images. The website applies its own colour treatments, cropping and displaced collage strips. No endorsement by an artist, photographer or museum is implied.

## Portrait of Aristotle

- Ancient marble portrait, unknown sculptor, mid-second century AD.
- Photograph by Szilas, 4 March 2013.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Portrait_of_Aristotle,_set_on_a_restored_bust,_Colosseum.jpg).
- The photographer expressly released the photograph into the public domain worldwide; the sculpture is also public domain.
- Downloaded the 960 x 1404 thumbnail on 4 November 2026. Cropped to x=0, y=80, width=960, height=1000; encoded as WebP at quality 78. The small version is 480 x 500.
- Files: `aristotle.webp`, `aristotle-small.webp`.
- The page masks the portrait, maps it to a blue/ice duotone and offsets two horizontal strips. The copy is hush's own writing, not a quotation attributed to Aristotle.

## Liberty Leading the People

- Eugène Delacroix, 1830. Collection of the Musée du Louvre.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Eug%C3%A8ne_Delacroix_-_Liberty_Leading_the_People.jpeg).
- Public-domain work and faithful reproduction, marked with [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/).
- Downloaded the 1280 x 1016 thumbnail on 4 November 2026. Encoded as WebP at quality 76. The small version is 768 x 610.
- Files: `liberty.webp`, `liberty-small.webp`.
- The page crops the composition responsively, maps it to a coral/ink duotone and displaces one narrow image strip on desktop.

## The Geographer

- Johannes Vermeer, 1669. Collection of the Städel Museum, Frankfurt am Main.
- [Downloaded reproduction and rights statement](https://commons.wikimedia.org/wiki/File:Johannes_Vermeer_-_The_Geographer_-_Google_Art_Project.jpg), from the Google Art Project reproduction on Wikimedia Commons.
- [Museum record](https://sammlung.staedelmuseum.de/en/work/the-geographer), which supplies the date and lists the picture copyright as Public Domain.
- The reproduction is marked with [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/).
- Downloaded the 960 x 1076 thumbnail on 4 November 2026. Encoded as WebP at quality 82, with a 480 x 538 responsive version. Original colours are preserved; a square display crop is applied with CSS.
- Files: `geographer.webp`, `geographer-small.webp`.
- The intelligence section shows the painting with its own visible caption and an original Three.js/SVG hush companion, considering an idea beside the map. Liberty's attribution stays with the preceding banner.

## Steve Jobs, 2010 (unused archive asset)

- Photograph by Matthew Yohe at WWDC, 7 June 2010. Crop by MetalGearLiquid, further cropped by CapLiber.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Steve_Jobs_Headshot_2010-CROP2.jpg).
- Used under [Creative Commons Attribution-ShareAlike 3.0 Unported](https://creativecommons.org/licenses/by-sa/3.0/).
- Downloaded the 960 x 1535 thumbnail on 4 November 2026. Encoded as WebP at quality 82; the responsive version is 480 x 768.
- Files: `steve-jobs.webp`, `steve-jobs-small.webp`. Both files and hush's monochrome, cyan/magenta strip and scanline photographic treatment are distributed under the same CC BY-SA 3.0 license. The reusable treatment is documented in `src/landing/story.css` under `.makers-art`, `.makers-portrait-base`, `.makers-slice` and `.makers-scanlines`.
- hush's original accompanying copy expresses inspiration from the Macintosh's creative spirit. It is not a quotation from Steve Jobs. The accompanying “Think different.” motif references Apple’s campaign, not an audio recording or quotation attributed to this photograph. The original Three.js/SVG hush mascot is a separate illustrative element. No Apple, estate or photographer endorsement is implied.

## The printing press (Der Buchdrucker), 1568

- Jost Amman, from the 1568 book of trades published with Hans Sachs's text. This depicts a sixteenth-century print workshop, not the invention of printing in 1568.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Buchdrucker-1568.png). The woodcut and reproduction are marked public domain / [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/).
- Downloaded the 751 x 879 PNG on 4 November 2026. Encoded as WebP at quality 83, plus a 450 x 527 responsive version at quality 80.
- Files: `printing-press.webp`, `printing-press-small.webp`.
- The website reverses the monochrome print into a cyan/ink duotone, masks the edge and displaces decorative strips using SVG/CSS. Surrounding words and the connecting thread are original code-native illustrations, not historic quotations or a real proof result.

## Ameca Generation 1

- Photograph by Willy Jackson, 27 October 2021, at Engineered Arts.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Ameca_Generation_1.jpg).
- Licensed under [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).
- Downloaded the 878 x 973 original on 4 November 2026. Cropped to x=49, y=0, width=780, height=973; WebP quality 82, plus a 480 x 599 version at quality 80.
- Files: `robot-portrait.webp`, `robot-portrait-small.webp`. Both files and hush's six-panel photographic adaptation are distributed under CC BY-SA 4.0. The adaptation is implemented in `src/verified/PortraitScene.ts` and the `.vm-portrait-fallback` / `.vm-portrait-fragment` styles in `src/verified/verified-editorial.css`.
- The robot image is recoloured in cyan and pink and split into displaced panels. It is a dimensional photo collage, not a 3D scan or an AI-generated image. The nearby message is an independent illustrative example, not attributed to the robot, its creator or photographer. No endorsement is implied.

## Twittering Machine (Die Zwitscher-Maschine)

- Paul Klee, 1922. Collection of the Museum of Modern Art, New York.
- [Source and rights statement](https://commons.wikimedia.org/wiki/File:Die_Zwitscher-Maschine_(Twittering_Machine),_1922_-_Paul_Klee.jpg).
- Public-domain work and faithful reproduction, marked with [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/).
- Downloaded the 994 x 1350 reproduction on 4 November 2026; WebP quality 80, plus a 480 x 652 version at quality 78.
- Files: `twittering-machine.webp`, `twittering-machine-small.webp`.
- CSS applies a restrained colour shift, rotated paper composition and edge mask. The example voice transcript and time are original illustrative content layered over the painting, not Klee's words or a historical recording.

Editorial artwork has visible credits beneath its composition. Files are hosted on hush's own site, with no third-party image requests.

## Rose sculpture

- Asset: Rose flower with stem, Innerscene Corp.
- Source: https://www.innerscene.com/tools/library/3d-parts/rose-flower-with-stem-b2a45a50
- Licence: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/
- Downloaded 10 November 2026. The source GLB also embeds the CC0 dedication.
- Adaptation: embedded textures removed with `scripts/prepare-rose.py`; pearl/lilac materials, composition, scaling and scroll-linked petal transforms by hush. Geometry remains from the source asset.
- Served locally as a Vite-hashed asset. No remote viewer, CDN or tracking requests.
