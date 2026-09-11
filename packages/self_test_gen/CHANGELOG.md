# Changelog

## 0.2.0

First release as its own package. The generator used to live inside
`self_test`, which meant every app that depended on `self_test` also pulled
`analyzer`, `source_gen`, `build` and `dart_style` at runtime. Splitting it out
is why the core package's only dependencies are now Flutter and `meta`.

### Added

- `selfTestBuilder`, wired through `build.yaml` with `auto_apply: dependents`,
  so adding this package to `dev_dependencies` is all the setup there is.

### Changed

- Generated controller methods are camelCase: `tapLoginBtn()` rather than
  `tap_login_btn()`, which is what the README always documented and what the
  lints expect.
- A private class generates a public controller. `_LoginFormState` becomes
  `LoginFormStateTestController`, so a test in another library can name it.
- The builder emits a standalone library rather than a `part`. Write no `part`
  directive, and do not import the generated file from its own source: that
  leaves the library unresolvable and the generator then finds no annotations
  at all.

### Fixed

- Annotations on class members are found. `LibraryReader.annotatedWith` only
  visits top-level declarations, so annotating a handler, which is what the
  README asks for, previously generated nothing.
- Two handlers annotated with the same id generate one method, not two
  identical ones that fail to compile.
- An id starting with a digit is prefixed so the method name is legal, and
  dashes, spaces and repeated separators in an id are tolerated.
- The generator runs on current Flutter. It pinned `analyzer` below 9, and
  analyzer 7 throws `Missing implementation of
  visitDotShorthandPropertyAccess` while serialising any library that reaches
  the Flutter framework, which from Dart 3.12 on is every library. It built on
  Flutter 3.35 and crashed on Flutter 3.47. The constraints are now
  `analyzer >=8.1.1 <15.0.0`, `source_gen ^4.2.4` and `build >=3.0.2 <5.0.0`,
  verified on both ends with byte-identical output.
