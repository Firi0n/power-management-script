# 🤝 Contributing to Universal Linux Power Management Script

First off, thank you for considering contributing to **Universal Linux Power Management Script**! It's open-source projects like this that make the Linux ecosystem so fantastic.

Contributions of all kinds are welcome:
- 🐛 **Reporting bugs**
- 💡 **Suggesting new features**
- 🔧 **Submitting Pull Requests (PRs)**
- 📖 **Improving documentation**

---

## 🚀 Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/power-management-script.git
   cd power-management-script
   ```
3. **Create a topic branch**:
   ```bash
   git checkout -b feature/my-new-feature
   ```

---

## 🧪 Testing Your Changes

Before submitting a PR, always test your changes locally using `--dry-run` and `--status`:

```bash
# Preview changes without modifying disk
sudo ./setup-power-management.sh --dry-run

# Run diagnostic status check
./setup-power-management.sh --status
```

---

## 📋 Pull Request Guidelines

- Ensure your code adheres to standard **Bash shell guidelines** (`shellcheck` clean).
- Keep changes **modular, non-destructive, and update-safe** (use `write_with_backup` for file writes).
- Write descriptive commit messages following Conventional Commits (e.g. `feat: ...`, `fix: ...`, `docs: ...`).
- Open a Pull Request against the `master` branch with a clear summary of your changes.

Thank you for helping make Linux laptop battery management better for everyone! 🔋⚡
