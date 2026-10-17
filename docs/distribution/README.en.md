# Software copyright application materials

[简体中文](README.md) | [English](README.en.md)

Blank templates for software copyright applications, with a tool that generates PDFs from the current source and your completed manual. Adapt them to your software version and filing requirements.

## 1. Fill in the templates

Copy these files into the Git-ignored `docs/software-copyright/` directory and enter your own details. Keep the shared templates blank:

| Template | Purpose |
| --- | --- |
| [Application fields](templates/copyright-application.md) | Check applicant, ownership, dates and related details |
| [Metadata](templates/copyright-metadata.example.json) | Rename to `copyright-metadata.json`; enter the software name, version, applicant and other details |
| [Software manual](templates/software-description.md) | Describe features, usage, implementation and data handling |

## 2. Generate PDFs

Install Python `reportlab` and prepare a licensed TTF font with Chinese coverage. Run from the repository root, replacing the font path with your actual file:

~~~sh
python3 tools/build_software_copyright_materials.py \
  --metadata docs/software-copyright/copyright-metadata.json \
  --description docs/software-copyright/software-description.md \
  --font /path/to/licensed-cjk.ttf
~~~

Outputs are saved in `docs/software-copyright/`:

- `source-materials.pdf`: 50 source lines per page; the first and last 30 pages if longer than 60 pages, otherwise the full listing.
- `software-description.pdf`: the software manual.

## 3. Review the materials

Check PDF contents and layout, and complete the official application as required by the receiving agency. Distinguish upstream code, your additions and third-party assets; report ownership and publication status accurately. MIT is not a copyright assignment. The tool helps prepare materials and does not guarantee registration; see [licensing](../legal.md). Keep completed records and exports out of Git.

Optional resources: [Android builds](../android-release.md) · [iOS development](../ios-setup.md) · [Store listing template](templates/store-listing.md).
