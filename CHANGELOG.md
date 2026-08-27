# Changelog

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
