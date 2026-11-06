# Living GIVE methodology (Jupyter Book 2)

The source for the public methodology website is in this directory. Existing technical documentation in `docs/` remains the implementation record; the book provides a navigable explanation of it.

## Preview locally

Install Jupyter Book 2 in a separate Python environment, then run:

```sh
python -m pip install "jupyter-book>=2.1,<3"
cd methodology
jupyter book start
```

Jupyter Book downloads and builds its web template on first use. No Julia model calculation is required.

## Build static HTML

```sh
cd methodology
jupyter book build --html
```

Generated assets are written to `methodology/_build/html`. The GitHub Actions workflow `.github/workflows/methodology-pages.yml` publishes this folder to GitHub Pages when changes are merged to `release-candidate`.

Enable **Settings → Pages → Build and deployment → Source → GitHub Actions** in the repository. Expected publication URL: https://mhm1g11.github.io/GIVE_and_beyond/ (only once deployed successfully).

## Editorial rules

1. Clearly distinguish implemented, experimental and proposed components. In particular, original GIVE agriculture is included, while the revised 2026 agriculture module is not.
2. Use primary literature and link each methodological claim to code or a validation note.
3. Never claim synthetic fixtures, placeholders or preliminary runs are validated policy estimates.
4. Do not add unpublished client material, restricted third-party data, external proprietary tables, secrets or heavyweight model outputs.
5. Never run production Monte Carlo/CIAM computations as part of website builds.
6. Every scenario result needs a precise input, commit, trial-design and provenance record.

Jupyter Book v2 uses `myst.yml`; the older `_config.yml` / `_toc.yml` scheme is not used.
