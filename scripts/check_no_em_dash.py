# Script to verify that no em dashes (Unicode U+2014) exist in any file
import sys
import os

def check_file(path):
    with open(path, "rb") as f:
        content = f.read()
    # Check for UTF-8 encoded em dash \xe2\x80\x94
    if b"\xe2\x80\x94" in content:
        return False
    return True

def main():
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    violations = []
    ignored_dirs = {".git", ".venv", "__pycache__", "build", ".mypy_cache"}
    
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ignored_dirs]
        for fname in filenames:
            if fname.endswith((".pl", ".py", ".md", ".c", ".h", ".json", ".txt", ".sh", ".toml", "Makefile")):
                fpath = os.path.join(dirpath, fname)
                if not check_file(fpath):
                    violations.append(os.path.relpath(fpath, root))
                    
    if violations:
        print("ERROR: Em dashes (U+2014) found in the following files:")
        for v in violations:
            print(f"  - {v}")
        sys.exit(1)
    else:
        print("SUCCESS: Zero em dashes found across all repository files.")
        sys.exit(0)

if __name__ == "__main__":
    main()
