#!/usr/bin/env python3
import os
import hashlib
import subprocess
import glob

REPO_DIR = "docs"

def get_hashes_and_size(filepath):
    """Calculate MD5, SHA1, SHA256 and gets file size."""
    size = os.path.getsize(filepath)
    md5 = hashlib.md5()
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    
    with open(filepath, 'rb') as f:
        while chunk := f.read(8192):
            md5.update(chunk)
            sha1.update(chunk)
            sha256.update(chunk)
            
    return size, md5.hexdigest(), sha1.hexdigest(), sha256.hexdigest()

def extract_control(deb_path):
    """Extracts the control file content from a deb using ar and tar."""
    try:
        # 1. Extract control.tar.* from ar archive to stdout
        # 'ar p' prints to stdout
        # We need to find the name of the control archive first (control.tar.gz or control.tar.xz)
        # Assuming control.tar.gz for standard debs or checking list
        
        # List content of ar
        ar_list = subprocess.check_output(["ar", "t", deb_path]).decode().splitlines()
        control_archive = next((x for x in ar_list if "control.tar" in x), None)
        
        if not control_archive:
            return None
            
        # Extract control archive content
        control_tar_data = subprocess.check_output(["ar", "p", deb_path, control_archive])
        
        # Extract 'control' file from the tar data
        # We perform this by piping to tar
        # tar -xOzf - ./control
        
        cmd = ["tar", "-xO", "--include=./control", "--include=control"]
        if control_archive.endswith(".gz"):
            cmd.append("-z")
        elif control_archive.endswith(".xz"):
            cmd.append("-J") # xz support might depend on tar version, usually -J or auto
        elif control_archive.endswith(".zst"):
            cmd = ["tar", "-xO", "--use-compress-program=unzstd", "--include=./control", "--include=control"]
            
        # pass tar data via stdin
        process = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate(input=control_tar_data)
        
        if process.returncode != 0:
            # Fallback: maybe just tar without compression flag if auto-detect works?
            # Or handle standard naming
            return None
            
        return stdout.decode('utf-8', errors='ignore')
        
    except Exception as e:
        # print(f"Error extracting {deb_path}: {e}")
        return None

def main():
    if not os.path.exists(REPO_DIR):
        print(f"Error: {REPO_DIR} does not exist.")
        return

    deb_files = glob.glob(os.path.join(REPO_DIR, "*.deb"))
    
    for deb_path in deb_files:
        control_content = extract_control(deb_path)
        if not control_content:
            print(f"Skipping {deb_path}: Could not read control file")
            continue
            
        # Clean up control content (ensure newline at end)
        control_content = control_content.strip()
        
        # Architecture override detection from filename
        filename = os.path.basename(deb_path)
        arch_override = None
        if "iphoneos-arm64" in filename:
            arch_override = "iphoneos-arm64"
        elif "iphoneos-arm" in filename:
            arch_override = "iphoneos-arm"

        # Update or add Architecture field
        lines = control_content.splitlines()
        new_lines = []
        arch_found = False
        for line in lines:
            if line.startswith("Architecture:"):
                arch_found = True
                if arch_override:
                    new_lines.append(f"Architecture: {arch_override}")
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        
        if not arch_found and arch_override:
            new_lines.append(f"Architecture: {arch_override}")

        depiction_found = any(l.startswith("Depiction:") for l in lines)
        sileo_depiction_found = any(l.startswith("SileoDepiction:") for l in lines)

        if not depiction_found:
            new_lines.append("Depiction: https://saihgupr.github.io/remotecompanion/")
        if not sileo_depiction_found:
            new_lines.append("SileoDepiction: https://saihgupr.github.io/remotecompanion/depiction.json")
            
        control_content = "\n".join(new_lines)

        # Calculate metadata
        size, md5, sha1, sha256 = get_hashes_and_size(deb_path)
        rel_path = os.path.relpath(deb_path, start=REPO_DIR)
        
        # Output stanza
        print(control_content)
        print(f"Filename: ./{rel_path}")
        print(f"Size: {size}")
        print(f"MD5sum: {md5}")
        print(f"SHA1: {sha1}")
        print(f"SHA256: {sha256}")
        print("") # Empty line between packages

if __name__ == "__main__":
    main()
