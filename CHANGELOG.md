# Changelog

## [1.3.0](https://github.com/gnugomez/majordomo/compare/v1.2.0...v1.3.0) (2026-11-05)


### Features

* a conversation timeline with avatars, reviews, and images in the preview ([6567d60](https://github.com/gnugomez/majordomo/commit/6567d60455f8e25bc611a91ca3bbc5a5faf29d8c))
* a Reviews board for every store, each starter board seeded once ([fdf1af1](https://github.com/gnugomez/majordomo/commit/fdf1af158120499d774b411cb299772a0fe59542))
* and/or groups and Apple Intelligence checks in label rules and board columns ([87fc913](https://github.com/gnugomez/majordomo/commit/87fc913d2f715cc012673f9d259470bc62a750b0))
* arrow keys move between cards on a board ([a59fe0d](https://github.com/gnugomez/majordomo/commit/a59fe0d9f5ad79c595e764fa9244714fb0e449ab))
* board columns can test merge status, and a review awaiting you isn't marked twice ([2f9ffaf](https://github.com/gnugomez/majordomo/commit/2f9ffafe7aa254118aefdbc6c994208f6827097c))
* boards that sort issues and pull requests by whose move it is, and previews that open at once ([3f16c69](https://github.com/gnugomez/majordomo/commit/3f16c693683070d6bc15ffeeed4c5b6e0cff691a))
* describe a rule with and/or groups and Apple Intelligence checks ([6ca56ad](https://github.com/gnugomez/majordomo/commit/6ca56ada36f3a731d10e832999ce6d9885e18328))
* filter the inbox by author, provider, or repository ([5d04a58](https://github.com/gnugomez/majordomo/commit/5d04a588b392381fd8a79e9f047d500d0d7a566f))
* merge status on board cards, from GitHub and GitLab ([58101ae](https://github.com/gnugomez/majordomo/commit/58101aed32538b656017f75163db884d336da3d4))
* one Filter button with a menu, like Mail's ([8a51acb](https://github.com/gnugomez/majordomo/commit/8a51acb2032d7187129e965cebe90f9dd598d8a6))
* one sidebar for every account, narrowed by the Provider filter ([31012e2](https://github.com/gnugomez/majordomo/commit/31012e2ef37b2961b954d5a95550e174c700d2da))
* preview a notification's issue or pull request in full ([23d846e](https://github.com/gnugomez/majordomo/commit/23d846e091c809964d150ed4733dda090cdb2238))
* review, checks and merge status on inbox rows ([a0c5fe8](https://github.com/gnugomez/majordomo/commit/a0c5fe8f05051acbc3eaca8a33190adde6eddfb4))
* search matches highlighted on board cards ([181a581](https://github.com/gnugomez/majordomo/commit/181a581e4e976e22b8ccb6842b7c9b9eb9b922f5))
* the date and unread filters narrow boards too ([68ee6f9](https://github.com/gnugomez/majordomo/commit/68ee6f9331df0af721d5b8c53e11a42167fe37f9))
* the preview shows where its target stands, who it is assigned to, and who is asked to review ([e851a66](https://github.com/gnugomez/majordomo/commit/e851a66774086345547614419230efa187d905b7))


### Bug Fixes

* a provider's token never follows a redirect to another host ([0db8a95](https://github.com/gnugomez/majordomo/commit/0db8a950e7c1993b8c3fba543e7e9f296d86d9b0))


### Refactoring

* a named type scale for the views' text ([a88fa05](https://github.com/gnugomez/majordomo/commit/a88fa05cf3cb94d8aee67952e2ff6b4ca6cf89ec))
* drop an unused row-field property and a stray comment ([068a6ad](https://github.com/gnugomez/majordomo/commit/068a6ada972aa7f8863e1c696237f3415477f7df))
* event-driven engine with one reaction table, state and event streams, and batched saves ([9280505](https://github.com/gnugomez/majordomo/commit/92805052905def75d2f687b26d38985d5b96153d))
* one helper floats the filter pills over the inbox and a board ([711c73e](https://github.com/gnugomez/majordomo/commit/711c73e21702b3c144492d79aa3a4e9700ff0c56))
* one palette, one flow layout, and one avatar for previews and boards ([696c6f5](https://github.com/gnugomez/majordomo/commit/696c6f55236c5d7ca390ed3d65f91152b5d4100f))
* provider errors say when the token itself was rejected ([0468360](https://github.com/gnugomez/majordomo/commit/0468360ec5178027293dba975e9a4e738b24394c))
* shared row, capsule, byline, and settings pieces; rows compare only what they draw ([3bd5bd6](https://github.com/gnugomez/majordomo/commit/3bd5bd6c511e2c2aa4d9c0183726faa15e697a88))
* the inbox list draws one row per element, threads and unfolded members alike ([5e3ed24](https://github.com/gnugomez/majordomo/commit/5e3ed24cc5f7014532a3cad67cfe586770c14e01))
* the rules list rows bind the rule they commit ([004b426](https://github.com/gnugomez/majordomo/commit/004b42618a4dfda058d33edd1458457559b106a3))
* the sidebar reads its rows and badges from the model, worked out once per change ([d624f9c](https://github.com/gnugomez/majordomo/commit/d624f9cc4507bdf503c9d9a89692f205f2e562de))

## [1.2.0](https://github.com/gnugomez/majordomo/compare/v1.1.0...v1.2.0) (2026-10-14)


### Features

* a glow in the model's colors, and a spotlight that dismisses on click ([b5181cc](https://github.com/gnugomez/majordomo/commit/b5181cc746ef8427fba41cd6aa103ac645c0a8d8))
* a Window menu and the standard hide commands ([093bffb](https://github.com/gnugomez/majordomo/commit/093bffbc607993c8016c6e2b25a0ae47fd6c549a))
* an Apple Intelligence summary on each inbox row ([527beb4](https://github.com/gnugomez/majordomo/commit/527beb4a80719ce4ce16c4422cc88e997bedc2c7))
* an Intelligence tab, and rules that move items rather than copy them ([6a71704](https://github.com/gnugomez/majordomo/commit/6a717042ca02aff413e3fbb2beb1b0005b1897ff))
* an Unread Only filter that keeps read rows where they are ([ae712b6](https://github.com/gnugomez/majordomo/commit/ae712b6a0a79a075fd1eeeea770fce57e80bd2e9))
* choose what inbox rows show, and in what order ([430f35b](https://github.com/gnugomez/majordomo/commit/430f35b09057e25d61b7cc451b61ce732294e718))
* deep sync on manual refresh and hourly ([e1a5a38](https://github.com/gnugomez/majordomo/commit/e1a5a387835c3e1a317b1a4a0ea231af337ad4c9))
* draft rules in your own words and suggest labels from patterns ([ad369c3](https://github.com/gnugomez/majordomo/commit/ad369c36b499005682fd7a8bad8db3ae8b88aa04))
* nothing at the sidebar's foot but sync activity ([7ab8725](https://github.com/gnugomez/majordomo/commit/7ab87254621541e87295ce97cb6f4c4fc30054ce))
* order the inbox by activity time and filter it by date ([1d74dc8](https://github.com/gnugomez/majordomo/commit/1d74dc8fd98245a16dc32ed3b4b27986adc939eb))
* organize the inbox with labels, custom inboxes, and rules ([21a4b01](https://github.com/gnugomez/majordomo/commit/21a4b013f6cda69a93c511086d251b320a07e49d))
* rename the Pulls category to Pull requests ([a792247](https://github.com/gnugomez/majordomo/commit/a7922470ffaf18a6ae3947e866232c7e222e3ac2))
* rules the on-device model judges, and a box for what they catch ([43c6f14](https://github.com/gnugomez/majordomo/commit/43c6f149ddb0843d2a3a11d183b6da0a547402dc))
* thread same-target notifications and searchable inbox ([88d3d89](https://github.com/gnugomez/majordomo/commit/88d3d897ba44faabbaf40799b4584536f1d9d049))
* update tokens in place and keep read state across account removal ([6389f0c](https://github.com/gnugomez/majordomo/commit/6389f0c4079cbb29a29b147d5ce362ac5d9ddcdb))


### Bug Fixes

* a mouse wheel scrolls the inbox a row per notch ([0b9823b](https://github.com/gnugomez/majordomo/commit/0b9823b210dab3b3e4f77abb3bda0273e1e1bb24))
* arrow keys walk the inbox instead of the sidebar ([86bf978](https://github.com/gnugomez/majordomo/commit/86bf9789967ec8928c3e5acecdf5317a08fbae69))
* keep every notification so search reaches old ones ([9116bec](https://github.com/gnugomez/majordomo/commit/9116bec1f3446c1547a6e67226287a4bf7fca191))
* the date filter keeps its place whether or not a row is selected ([0d115ca](https://github.com/gnugomez/majordomo/commit/0d115cab795fcc80dc16ce98d730309682b8a2e8))
* unread items sort above read in every list ([9942ea9](https://github.com/gnugomez/majordomo/commit/9942ea928bbd5581712f271857747b28dea711d0))


### Refactoring

* one catalog owns the full label and rule set ([9b8c41e](https://github.com/gnugomez/majordomo/commit/9b8c41e349a034b9a610bea488ae81ab0ec44732))

## [1.1.0](https://github.com/gnugomez/majordomo/compare/v1.0.2...v1.1.0) (2026-09-08)


### Features

* mark-read button in the selection toolbar ([f1232b7](https://github.com/gnugomez/majordomo/commit/f1232b73f30c60d2b6d47464527c94fc97c4bbaf))
* provider body content in the preview ([7dc1fdd](https://github.com/gnugomez/majordomo/commit/7dc1fdd47a5a8fa3d802bcebec753a410eb45dca))

## [1.0.2](https://github.com/gnugomez/majordomo/compare/v1.0.1...v1.0.2) (2026-09-08)


### Bug Fixes

* enforce the main window's minimum size ([a05cac4](https://github.com/gnugomez/majordomo/commit/a05cac46e13d231f22c0355fa74dff7889761e39))

## [1.0.1](https://github.com/gnugomez/majordomo/compare/v1.0.0...v1.0.1) (2026-09-08)


### Bug Fixes

* installed builds crashed at launch resolving the tray-icon bundle ([8e92325](https://github.com/gnugomez/majordomo/commit/8e9232538f096d798036ba4a8e11cf5459561a8c))

## [1.0.0](https://github.com/gnugomez/majordomo/compare/v0.4.0...v1.0.0) (2026-09-08)


### ⚠ BREAKING CHANGES

* native Swift/SwiftUI rewrite, Electron retired ([#10](https://github.com/gnugomez/majordomo/issues/10))

### Features

* native Swift/SwiftUI rewrite, Electron retired ([#10](https://github.com/gnugomez/majordomo/issues/10)) ([9d377fe](https://github.com/gnugomez/majordomo/commit/9d377fef7c55083557d7dfd5928b0869a2630548))
* show unread count on the dock and launcher badge ([7676990](https://github.com/gnugomez/majordomo/commit/7676990b10acca7490292a1fd935c1885e742831))

## [0.4.0](https://github.com/gnugomez/majordomo/compare/v0.3.1...v0.4.0) (2026-09-03)


### Features

* add a resizable main window with inbox list and preview pane ([54a9d92](https://github.com/gnugomez/majordomo/commit/54a9d924d633daa91794f030060853c8563da42d))
* add an Assigned category for items assigned to you ([40679a2](https://github.com/gnugomez/majordomo/commit/40679a20fe2c69bbdd80c27a0df848249968b01e))
* browse the main window inbox with the arrow keys ([a121d38](https://github.com/gnugomez/majordomo/commit/a121d38d0047c7d6cab9d632e981937b673f5343))
* drop the translucent background setting on macOS ([82c2eff](https://github.com/gnugomez/majordomo/commit/82c2eff9288fdc0bfcccd8eecf7200c44ce981a2))
* give the main window the frosted sidebar material ([2fff0af](https://github.com/gnugomez/majordomo/commit/2fff0af43b9ccd78b1f10bdf655a9741ceea61fd))
* lay the main window out as sidebar, inbox and preview ([5e903be](https://github.com/gnugomez/majordomo/commit/5e903be66f517ccb323fcbadc57a490b9fa800d4))
* open settings from the main window ([d9f47cc](https://github.com/gnugomez/majordomo/commit/d9f47cce042ef60e2fa7e0124875f5d99892a63f))
* open the main window from the popover title instead of a fourth icon ([95e13c3](https://github.com/gnugomez/majordomo/commit/95e13c3f624361f8c2b76b913a04dcf2dff4306b))
* remember the main window's size and position ([25bd8bd](https://github.com/gnugomez/majordomo/commit/25bd8bd6b924ffe2b737798b3198f79423b5ddf6))
* resize the main window's sidebar and inbox ([2cd7f2f](https://github.com/gnugomez/majordomo/commit/2cd7f2fc3ef341d1b885065ec4d79b3280ec7557))
* speak one vocabulary for GitHub and GitLab item reasons ([585918a](https://github.com/gnugomez/majordomo/commit/585918a1ba3b2d6688dcdf2b3824d43547039875))
* swap the settings text button for a cog and restyle the double check ([81cfd99](https://github.com/gnugomez/majordomo/commit/81cfd9937ce70c52f16131e87f236e1d681d4f5a))
* updating app icon ([ed2d80f](https://github.com/gnugomez/majordomo/commit/ed2d80fe8b6519adbc15893ec4a311d32a6db151))


### Bug Fixes

* remove the stray focus outline in the main window ([1dfbe33](https://github.com/gnugomez/majordomo/commit/1dfbe339301af2865e6816ad18950005900dbf06))
* updating app icon ([2678854](https://github.com/gnugomez/majordomo/commit/2678854ce8f7a1ef328de69f5ecbffb42ee7682d))

## [0.3.1](https://github.com/gnugomez/majordomo/compare/v0.3.0...v0.3.1) (2026-09-01)


### Bug Fixes

* sort GitLab items by target activity instead of todo creation ([c63b9a1](https://github.com/gnugomez/majordomo/commit/c63b9a1c8ff9773054cd2586355cc82f5e684fd7))

## [0.3.0](https://github.com/gnugomez/majordomo/compare/v0.2.1...v0.3.0) (2026-09-01)


### Features

* adopt the Icon Composer app icon on every platform ([148bc53](https://github.com/gnugomez/majordomo/commit/148bc53c087bcac2acfe302c4389aa4829420244))


### Bug Fixes

* don't resurrect items when a sync overlaps a disconnect ([409470c](https://github.com/gnugomez/majordomo/commit/409470c8d6a32e5f90dc1b49a7611c53a3409126))
* keep a failed connect's error visible until the next attempt ([5d6ea71](https://github.com/gnugomez/majordomo/commit/5d6ea71e46beee4fd7f2fcc9b3a3782821eeed54))
* notification title falls back to the provider name ([5ae97a0](https://github.com/gnugomez/majordomo/commit/5ae97a0b434c6842e77777546001cb842253f756))
* only trust item absence after a complete, uncapped fetch ([c046515](https://github.com/gnugomez/majordomo/commit/c046515d98b431c9b8c51f8f51ceb4b9b893360d))
* pre-bridge first paint guesses the host platform ([a207004](https://github.com/gnugomez/majordomo/commit/a207004909c046d4f09cb0f343fec446ab0e5ba8))
* run the popover renderer sandboxed ([737f9b5](https://github.com/gnugomez/majordomo/commit/737f9b5d2dc558c4da4eb1ab1151f3d1ca462d63))


### Refactoring

* openItem ignores unknown item ids ([10aedc2](https://github.com/gnugomez/majordomo/commit/10aedc2309f4b12fba41e52eb7bd185d6a04ca08))
* share the acrylic-support check ([f7d718b](https://github.com/gnugomez/majordomo/commit/f7d718b3e5001f8f4aaf6b321513fb1257b57e15))

## [0.2.1](https://github.com/gnugomez/majordomo/compare/v0.2.0...v0.2.1) (2026-08-27)


### Bug Fixes

* hover-expanded repo no longer paints over the capsule ([c1d7d60](https://github.com/gnugomez/majordomo/commit/c1d7d6068ac86ed228b10a7cf39901eb74616a4f))
* no focus ring flash on open; keyboard focus ring is muted ([8dc9277](https://github.com/gnugomez/majordomo/commit/8dc9277f611c1ec49f4004b3d06e253b25be99d8))
* no hover highlight on section headers ([6f8e902](https://github.com/gnugomez/majordomo/commit/6f8e9020ff7c2c24f3c650e454ff491db5b58277))
* no press highlight on section headers either ([6e44710](https://github.com/gnugomez/majordomo/commit/6e447108a69204a6a46c581bee7bba768765f68b))
* prompt-free token storage on macOS via safeStorage ([afb4aed](https://github.com/gnugomez/majordomo/commit/afb4aedb6c7b6cbc2e87f73b5993f2fef3923301))
* read each token from the keychain once per run ([a720c8f](https://github.com/gnugomez/majordomo/commit/a720c8f44372521e13fb41b7b942c822b3a5cd70))


### Refactoring

* safeStorage for tokens on every platform, keyring removed ([9f57fb6](https://github.com/gnugomez/majordomo/commit/9f57fb65871471ff12b09421b77f761d33ccd107))

## [0.2.0](https://github.com/gnugomez/majordomo/compare/v0.1.1...v0.2.0) (2026-08-27)


### Features

* popover resizes to fit its content, without a scrollbar ([e29f8bf](https://github.com/gnugomez/majordomo/commit/e29f8bf9763f302cceef14b8e4d34466d69046de))
* show item state with GitHub's iconography and colors ([c1b1c81](https://github.com/gnugomez/majordomo/commit/c1b1c81182de46661194cf50d12449db24bd093a))
* show who wrote each item ([cb6e849](https://github.com/gnugomez/majordomo/commit/cb6e84906b4e1a590c20d0f119b2d23c5fe8a223))


### Bug Fixes

* hovering a truncated repo or author reveals the full text ([57c9f35](https://github.com/gnugomez/majordomo/commit/57c9f354b7f98d2b244aa5d552cf97c043b7965a))
* keep a persistent local inbox; items read on the web arrive and stay read ([813b052](https://github.com/gnugomez/majordomo/commit/813b052cdf76f4e5ba01457023ea289a7c1b0625))
* the settings control is a text button ([c5538dc](https://github.com/gnugomez/majordomo/commit/c5538dc0da5dd1702dadc880f7502b80e606e12b))

## [0.1.1](https://github.com/gnugomez/majordomo/compare/v0.1.0...v0.1.1) (2026-08-27)


### Bug Fixes

* notification clicks open the item (keep notifications referenced) ([ea4ca8b](https://github.com/gnugomez/majordomo/commit/ea4ca8b7bf079ab9a98a8110233402a986e4e295))

## 0.1.0 (2026-08-27)


### Features

* automated releases via release-please with stable CI signing ([af8e789](https://github.com/gnugomez/majordomo/commit/af8e78928e8cdaa1792b3137b859b5e30cae1ef1))
* collapsible inbox with overview and per-kind sections ([b65e3f1](https://github.com/gnugomez/majordomo/commit/b65e3f140fbca5a89b0ac0755b38d27e46c3f8f8))
* Majordomo, a macOS menu-bar inbox for GitHub and GitLab ([9d29f26](https://github.com/gnugomez/majordomo/commit/9d29f264a110f1bc9ee00f0e8ccafeff28518180))
* native Liquid Glass popover with system accent and launch at login ([d6d1f8d](https://github.com/gnugomez/majordomo/commit/d6d1f8d7e5bc06cec811ce97b7eeaf7365cc6e63))
* package and install as a standalone Majordomo.app ([cc334b0](https://github.com/gnugomez/majordomo/commit/cc334b06c92c2aeb7e4599cf179fc403406d36ea))
* Windows and Linux support with OS-keychain tokens and per-OS installers ([a4b6384](https://github.com/gnugomez/majordomo/commit/a4b6384a733f37e2300c92e40a0397634af5d8c9))


### Refactoring

* React UI, library-backed providers, clearer layout ([50dfc78](https://github.com/gnugomez/majordomo/commit/50dfc78cbddb3ad3e6e7ba8416d4a96cdae6dcc5))
