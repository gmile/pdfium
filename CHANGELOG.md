# Changelog

## 0.2.0

### Breaking changes

- `PDFium.load_document/1`, `PDFium.load_memory_document/1` and
  `PDFium.with_memory_document/2` are gone. Use `PDFium.open_document/2` and
  `PDFium.with_document/3`, which take a path or `{:bytes, contents}`.
- `PDFium.Toolbox` jobs no longer take an output path. `stamp`, `overlay`,
  `flatten`, `merge` and `extract_pages` answer `{:ok, binary}`, and the
  `_to_binary` variants are gone. Write the result with `File.write/2`.
- `PDFium.Toolbox.flatten` always answers with the document. It no longer
  answers `{:ok, :nothing_to_do}`.
- Operations that make nothing answer `:ok`: `PDFium.save/3` instead of
  `{:ok, :saved}`, `PDFium.import_pages/4` instead of `{:ok, :imported}`,
  `PDFium.flatten_page/3` instead of `{:ok, :flattened}` or
  `{:ok, :nothing_to_do}`.
- `PDFium.save/3` reports a failed write with the posix reason, such as
  `{:error, :enoent}`, instead of `{:error, :output_open_failed}`.
- `PDFium.stamp/2` stamps in place and answers `:ok`. The old `PDFium.stamp/4`,
  which wrote to a path, and `PDFium.stamp_in_place/2` are gone. A stamp that
  fails now leaves the document as it was.
- `PDFium.get_page_bitmap/3` answers `{:ok, {pixels, width, height}}` instead of
  `{:ok, pixels, width, height}`.
- `PDFium.get_page_sizes/1` takes one document and answers a list of sizes,
  instead of taking a list of documents and answering a list of lists.
- `PDFium.get_page_boxes/1` reports the box a page is drawn in, its MediaBox
  clipped by its CropBox, instead of the bare MediaBox. The two differ only on
  pages with a CropBox.
- `PDFium.create_document/0` always answers `{:ok, document}`.
- `:xfa_load` and `:xfa_layout` are no longer load errors.
- `PDFium.Toolbox` answers `{:error, :empty_page}` instead of
  `{:error, :empty_overlay}` for a page with no area.

### Added

- `password:` option to `PDFium.open_document/2` and `PDFium.with_document/3`.
- `PDFium.Toolbox.render_pages!/2`, a stream of rendered pages.
- Documentation with an example for every public function.

### Fixed

- Rendering a large page at a high resolution no longer overflows the size of
  the pixel buffer.
