# Clean release branch

`release-candidate` is a new-root branch in [mhm1g11/GIVE_and_beyond](https://github.com/mhm1g11/GIVE_and_beyond). It keeps the upstream MIT attribution and Julia package identity while excluding private research archives and historical generated outputs. Existing `main` and its history are preserved.

Clone only the clean branch:

```sh
git clone --single-branch --branch release-candidate https://github.com/mhm1g11/GIVE_and_beyond.git
```

A clean branch does not remove files already present in older public history. Ordinary clones that include all branches can still fetch historical objects. Do not force-push, delete old main or merge unrelated roots merely to change the default branch.

## Make the clean branch the default

After confirming the branch contents on GitHub, open repository **Settings -> Branches -> Default branch** (or **Settings -> General -> Default branch**, depending on the GitHub interface), choose `release-candidate` and confirm. This changes the default without rewriting or deleting `main`. Keep the single-branch clone command in README.

Future changes should be ordinary commits/fast-forward pushes on the clean branch. Update through reviewed branches based on `release-candidate`; no history rewrite is needed. Keep external datasets, user scenarios with restricted contents, results and local preparation material ignored. Check staged paths, sizes, secrets and notices before publishing.
