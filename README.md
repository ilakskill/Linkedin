# AI Image Renamer for Jewelry Photos

This PowerShell script renames product photos using AI image classification.

I built it to help my aunt organize a large jewelry photo library. Her images were named IMG_0001.jpg, IMG_0002.jpg, and so on. Finding the right photo slowed listings and inventory work. This script fixes that by creating consistent, searchable filenames and logs every change before anything is renamed.

---

## What it does

You point the script at a folder of images.

For each image, it:

• Sends the photo to Google Gemini Vision
• Extracts four attributes

* Category
* Color
* Style
* Material
  • Builds a rename plan
  • Writes the plan to a CSV file
  • Renames files only when you approve

Optional behavior:

• Writes metadata into the image files using ExifTool

---

## Filename format

Category ReverseDateKey (Color) (Style) (Material) Date_Sequence.ext

Example

Ring 99991231215822 (Gold) (Solitaire) (Diamond) 20240112_001.jpg

Why this format works

• Alphabetical sorting shows newest items first within each category
• Each filename reads like an inventory label
• Files stay readable without opening them

---

## Requirements

• Windows PowerShell 5.1 or PowerShell 7
• Google AI Studio API key
• Internet access

Optional

• ExifTool for metadata writing

---

## Setup

### 1. Get an API key

Create a key in Google AI Studio.

Set it as an environment variable:

GOOGLE_API_KEY

Or pass it directly with the -ApiKey parameter.

---

### 2. Place the script

Example location:

C:\Tools\Rename-JewelryPhotos.ps1

---

## Usage

### Preview mode

Preview is the default and safest mode.

Example:

.\Rename-JewelryPhotos.ps1 -Path "D:\Photos\Jewelry"

What happens:

• No files are renamed
• A rename-plan.csv file is created
• Console output shows classification results

---

### Apply renames

After reviewing the CSV plan:

.\Rename-JewelryPhotos.ps1 -Path "D:\Photos\Jewelry" -Apply

Renames run in two steps using temporary filenames to avoid collisions.

---

### Recurse into subfolders

-Recurse

---

### Test on a small batch

-Limit 25

---

### Slow down API calls

-DelayMs 200

Useful if you hit API rate limits.

---

## Logs and reports

rename-plan.csv

• One row per image
• Source path and target path
• Category, color, style, material
• Planned action

rename-errors.csv

• API failures
• Status codes and messages

rename-report_YYYYMMDD_HHMMSS.csv

• Final rename results
• Success or failure per file
• Metadata write status if enabled

---

## Writing metadata into images

To enable metadata writing:

• Install ExifTool
• Ensure it is available in PATH or pass -ExifToolPath

Run with:

-WriteMetadata

The script writes:

• Title
• Subject
• Comment
• Keywords for category, color, style, and material

This improves filtering and search in Windows Explorer and DAM tools.

---

## Customization

You can adapt this script for other products.

Common changes:

• Edit category lists and normalization rules
• Adjust the AI prompt to match your product types
• Reuse the naming pattern for shoes, watches, tools, or inventory photos

---

## Safety notes

• Always run preview mode first
• Keep backups of original images
• Treat the "Other" category as a review bucket

---

## Why this exists

Small businesses lose hours to manual photo cleanup.

This script removes that work.
It turns AI into a boring, repeatable helper.
That is the point.
