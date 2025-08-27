# lncRNA Discovery Workflow

A robust pipeline for discovering long non-coding RNAs (lncRNAs) from RNA-seq data, improved for reliability and ease of use.

## Overview

This workflow takes RNA-seq reads, discovers lncRNAs, generates count matrices, and filters GTF and FASTA files based on count matrix outcomes. It is designed to run on different computing environments with varying tool installations.

## Files

- **`workflow.qmd`** - Original workflow (Quarto document)
- **`workflow-original.qmd`** - Backup copy of original workflow
- **`workflow-improved.qmd`** - Enhanced robust version with error checking and configuration management
- **`13.1-filter_count_matrix.py`** - Python script for filtering count matrices (now included)
- **`config.yaml`** - Configuration file (auto-generated on first run)

## Improvements in Enhanced Version

### 🔧 Configuration Management
- YAML-based configuration file for different environments (RAVEN, KLONE)
- Automatic environment detection
- Configurable parameters (threads, paths, thresholds)

### 🛡️ Error Checking & Validation
- Comprehensive file validation (existence, size, format)
- Detection of HTML downloads instead of expected files
- Process exit code checking
- Input/output validation at each step

### 🔄 Restart Capability
- Ability to restart pipeline from any step
- Automatic detection of existing outputs
- Skip completed steps to save time

### 📝 Logging & Progress Tracking
- Detailed timestamped logging
- Step-by-step progress reporting
- Error logging with context
- Summary statistics generation

### 🌐 Robust Downloads
- Retry logic for network operations
- Timeout handling
- Validation of downloaded files
- Graceful failure handling

### 🔍 Tool Management
- Automatic tool detection in system PATH
- Fallback to configured paths
- Validation of required dependencies
- Support for multiple computing environments

## Quick Start

### Using the Enhanced Version

1. **Run the improved workflow:**
   ```bash
   # Render the Quarto document
   quarto render workflow-improved.qmd
   ```

2. **Or run the generated script directly:**
   ```bash
   # The workflow creates a standalone script
   ./robust_lncrna_pipeline.sh
   ```

3. **Restart from a specific step (if needed):**
   ```bash
   RESTART_FROM_STEP=5 ./robust_lncrna_pipeline.sh
   ```

### Configuration

On first run, a `config.yaml` file is created with default settings. Edit this file to:

- Set tool paths for your environment
- Adjust thread count and other parameters
- Configure data sources and output directories
- Set analysis thresholds

Example configuration:
```yaml
threads: 8
restart_from_step: 1
data_dir: "../data/12-Peve-lncRNA-discovery"
output_dir: "../output/12-Peve-lncRNA-discovery"
min_transcript_length: 200
min_coverage: 10
tool_paths:
  auto_detect: true
  raven:
    hisat2_dir: "/home/shared/hisat2-2.2.1/"
    samtools_dir: "/home/shared/samtools-1.12/"
    # ... other tools
```

## Pipeline Steps

1. **Setup & Download** - Download reference genome, GTF, GFF, and FASTQ files
2. **HISAT2 Alignment** - Build genome index and align RNA-seq reads
3. **SAM to BAM** - Convert and sort alignment files
4. **StringTie Assembly** - Assemble transcripts and merge across samples
5. **GFFCompare** - Compare assembled transcripts with reference annotations
6. **Candidate Filtering** - Filter for novel lncRNA candidates based on class codes
7. **CPC2 Analysis** - Assess coding potential of candidates
8. **Final Processing** - Create final lncRNA annotations and sequences
9. **Count Matrix** - Generate expression count matrix (optional)

## Requirements

### Software Dependencies
- HISAT2 (alignment)
- samtools (SAM/BAM processing)
- StringTie (transcript assembly)
- gffcompare (transcript comparison)
- bedtools (sequence extraction)
- CPC2 (coding potential assessment)
- featureCounts (read counting, optional)
- Python 3 (for filtering scripts)
- R with yaml package (for configuration)

### System Requirements
- Multi-core CPU (configurable thread count)
- Sufficient RAM for genome indexing and alignment
- Adequate disk space for intermediate files
- Network access for downloading reference files

## Environment Setup

### RAVEN Environment
The workflow is pre-configured for the RAVEN computing environment with tools in `/home/shared/`.

### KLONE Environment
Alternative paths are provided for the KLONE computing environment. Update `config.yaml` as needed.

### Custom Environment
Set `auto_detect: false` in `config.yaml` and provide custom tool paths.

## Troubleshooting

### Common Issues

1. **Missing tools**: The workflow will check for required tools and report missing dependencies
2. **Download failures**: Network issues are handled with retry logic
3. **Corrupted downloads**: HTML files are detected and downloads are retried
4. **Insufficient resources**: Adjust thread count in configuration
5. **Restart needed**: Use `RESTART_FROM_STEP` to resume from any point

### Log Files
Check `../logs/12-Peve-lncRNA-discovery/workflow.log` for detailed execution logs.

### File Validation
The workflow validates all intermediate files for existence, size, and format.

## Output Files

Key output files in the output directory:

- `lncRNA.gtf` - Final lncRNA annotations
- `lncRNA.fasta` - Final lncRNA sequences
- `lncRNA.bed` - Final lncRNA coordinates
- `CPC2.txt` - Coding potential analysis results
- `stringtie_merged.gtf` - Merged transcript assemblies
- Count matrix files (if generated)

## Contributing

To contribute improvements:

1. Test changes with the enhanced workflow
2. Ensure backward compatibility with original workflow
3. Update documentation as needed
4. Add appropriate error checking and validation

## License

This workflow is provided as-is for research purposes.