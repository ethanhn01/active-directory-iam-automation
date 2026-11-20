# Publish this project to your GitHub profile

This project is intentionally distributed as a ready-to-upload folder. You own your repository, and you should make the initial commit after inspecting the files and running the mock tests.

## GitHub Desktop (beginner-friendly)

1. Unzip the project to a local folder (for example, `Documents/active-directory-iam-automation`).
2. Install GitHub Desktop from https://desktop.github.com/ and sign in to GitHub.
3. Choose **File > Add local repository**, browse to the project directory, and select **Create a repository here** if prompted.
4. Commit all project source files with a message such as `Initial IAM automation lab project`.
5. Click **Publish repository**, choose `active-directory-iam-automation`, set the visibility to **Public** if you want employers to view it, and publish.
6. Visit the repository's **Actions** tab to inspect the automated test result. If you get a failure, troubleshoot it and push a corrective commit. Do not claim the tests passed until they have.

## Terminal alternative

After extracting the ZIP, open a terminal **inside** the project folder:

```bash
git init -b main
git add .
git commit -m "Initial IAM automation lab project"
```

On GitHub, create a **new empty** repository named `active-directory-iam-automation` (do not initialize it with a README because the project already has one). Then:

```bash
git remote add origin https://github.com/ethanhn01/active-directory-iam-automation.git
git push -u origin main
```

If Git asks for your identity, configure your name and preferred email locally. GitHub uses browser/credential manager authentication, not your GitHub password pasted in a terminal.

## Before you add it to your resume

- Run `./tests/Run-Tests.ps1` using PowerShell, inspect that all checks passed, and fix any issues.
- Inspect the Actions tab for CI results after publishing.
- Run the mock demo and capture your own screenshots.
- Optionally build the isolated AD test domain and confirm real AD provider behavior.
- Customize the README with your verified learnings and photos from the fictional lab.
- Use your actual repository URL on your resume and LinkedIn.
