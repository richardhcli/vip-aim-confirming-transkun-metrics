import os
import sys
import shutil
import argparse
import zipfile
import urllib.request
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="Acquire and prepare the MAESTRO dataset.")
    parser.add_argument("--source", required=True, help="HTTP URL to a zip, or local directory path")
    parser.add_argument("--dest", required=True, help="Destination directory to save/link the dataset")
    parser.add_argument("--rebuild", action="store_true", help="Force delete and recreate the dataset")
    args = parser.parse_args()

    source_path = args.source
    dest_path = Path(args.dest)

    # --- 1. Rebuild Logic ---
    if dest_path.exists():
        if args.rebuild:
            print(f"Rebuild flag set. Removing existing dataset at {dest_path}...")
            if dest_path.is_symlink():
                dest_path.unlink()
            else:
                shutil.rmtree(dest_path)
        else:
            print(f"Dataset already exists at {dest_path}. Skipping acquisition.")
            return

    # Create parent directories if they don't exist
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    # --- 2. HTTP Download Mode ---
    if source_path.startswith("http://") or source_path.startswith("https://"):
        print(f"HTTP Source detected. Downloading from {source_path}...")
        zip_path = dest_path.parent / "maestro_temp.zip"
        
        try:
            # WHAT: Retrieves the file from the web and saves it locally.
            urllib.request.urlretrieve(source_path, zip_path)
            
            print(f"Download complete. Extracting to {dest_path}...")
            # WHAT: Extracts the contents of the zip file.
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(dest_path)
                
            print("Cleaning up temporary zip file...")
            os.remove(zip_path)
            
        except Exception as e:
            print(f"ERROR during download/extraction: {e}")
            sys.exit(1)

    # --- 3. Local Cluster Mode (Symlink) ---
    else:
        print(f"Local source detected at {source_path}.")
        local_src = Path(source_path)
        
        if not local_src.exists():
            print(f"ERROR: Local source directory does not exist: {local_src}")
            sys.exit(1)
            
        print(f"Creating symbolic link to optimize cluster storage...")
        # WHAT: Creates a lightweight pointer instead of copying 130GB of audio.
        # WHY: Saves hours of I/O time and prevents Gilbreth quota violations.
        try:
            os.symlink(local_src, dest_path)
        except OSError as e:
            print(f"ERROR creating symlink: {e}")
            sys.exit(1)

    # --- 4. Preprocessing Hook ---
    print("\nExecuting preprocessing steps...")
    # Add any custom preprocessing logic here (e.g., converting sample rates, filtering CSVs)
    # ...

    print(f"\nDataset successfully acquired and ready at: {dest_path}")

if __name__ == "__main__":
    main()