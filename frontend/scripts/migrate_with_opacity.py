import os
import re

DIRECTORY = r'c:\Users\sanje\apps\Vayu\snehayog\frontend\lib'

def migrate_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False

    if 'withOpacity' not in content:
        return False

    # Regex to find .withOpacity(0.5) and replace with .withValues(alpha: 0.5)
    pattern = r'\.withOpacity\((.*?)\)'
    replacement = r'.withValues(alpha: \1)'
    
    new_content = re.sub(pattern, replacement, content)

    if new_content != content:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            return True
        except Exception as e:
            print(f"Error writing {filepath}: {e}")
    return False

def main():
    count = 0
    total_files = 0
    for root, _, files in os.walk(DIRECTORY):
        for file in files:
            if file.endswith('.dart'):
                total_files += 1
                if migrate_file(os.path.join(root, file)):
                    count += 1
    print(f"Migrated {count} files out of {total_files} scanned.")

if __name__ == "__main__":
    main()
