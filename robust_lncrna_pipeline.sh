#!/bin/bash

# Robust lncRNA Discovery Pipeline
# Standalone version that doesn't require R for execution
# Configuration can be done via environment variables or config file

set -euo pipefail  # Exit on errors, undefined variables, pipe failures

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
DEFAULT_THREADS=8
DEFAULT_DATA_DIR="../data/12-Peve-lncRNA-discovery"
DEFAULT_OUTPUT_DIR="../output/12-Peve-lncRNA-discovery"
DEFAULT_LOG_DIR="../logs/12-Peve-lncRNA-discovery"
DEFAULT_MIN_TRANSCRIPT_LENGTH=200
DEFAULT_MIN_COVERAGE=10
DEFAULT_MIN_SAMPLE_FRACTION=0.5

# URLs and sources
FASTQ_SOURCE="https://gannet.fish.washington.edu/gitrepos/urol-e5/timeseries_molecular/E-Peve/output/01.00-E-Peve-RNAseq-trimming-fastp-FastQC-MultiQC/"
FASTQ_SUFFIX="fq.gz"
GENOME_SOURCE="https://gannet.fish.washington.edu/seashell/snaps/Porites_evermanni_v1.fa"
GTF_SOURCE="https://github.com/urol-e5/timeseries_molecular/raw/99f0563a067ca9d010cb206dfd44b36d8f77de00/E-Peve/data/Porites_evermanni_validated.gtf"
GFF_SOURCE="https://github.com/urol-e5/timeseries_molecular/raw/99f0563a067ca9d010cb206dfd44b36d8f77de00/E-Peve/data/Porites_evermanni_validated.gff3"
GFFPATTERN='class_code "u"|class_code "x"|class_code "o"|class_code "i"'

# Load configuration from environment or use defaults
THREADS=${THREADS:-$DEFAULT_THREADS}
DATA_DIR=${DATA_DIR:-$DEFAULT_DATA_DIR}
OUTPUT_DIR=${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}
LOG_DIR=${LOG_DIR:-$DEFAULT_LOG_DIR}
MIN_TRANSCRIPT_LENGTH=${MIN_TRANSCRIPT_LENGTH:-$DEFAULT_MIN_TRANSCRIPT_LENGTH}
MIN_COVERAGE=${MIN_COVERAGE:-$DEFAULT_MIN_COVERAGE}
MIN_SAMPLE_FRACTION=${MIN_SAMPLE_FRACTION:-$DEFAULT_MIN_SAMPLE_FRACTION}
RESTART_FROM_STEP=${RESTART_FROM_STEP:-1}

# Derived paths
FASTQ_DIR="${DATA_DIR}/fastq"
GENOME_FASTA="${DATA_DIR}/genome.fasta"
GENOME_GTF="${DATA_DIR}/genome.gtf"
GENOME_GFF="${DATA_DIR}/genome.gff"
GENOME_INDEX="${OUTPUT_DIR}/genome.index"

# Logging function
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] $level: $message"
    
    echo "$log_entry"
    
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    echo "$log_entry" >> "$LOG_DIR/workflow.log" 2>/dev/null || true
}

# Tool paths - environment detection
detect_environment() {
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    
    if echo "$hostname" | grep -qi "raven"; then
        echo "raven"
    elif echo "$hostname" | grep -qi "klone"; then
        echo "klone"
    else
        echo "raven"  # Default
    fi
}

# Set tool paths based on environment
ENV=$(detect_environment)

case "$ENV" in
    "raven")
        HISAT2_DIR="/home/shared/hisat2-2.2.1/"
        SAMTOOLS_DIR="/home/shared/samtools-1.12/"
        STRINGTIE_DIR="/home/shared/stringtie-2.2.1.Linux_x86_64/"
        GFFCOMPARE_DIR="/home/shared/gffcompare-0.12.6.Linux_x86_64/"
        BEDTOOLS_DIR="/home/shared/bedtools2/bin/"
        CPC2_DIR="/home/shared/CPC2_standalone-1.0.1/bin/"
        CONDA_PATH="/opt/anaconda/anaconda3/bin/conda"
        FEATURECOUNTS_PATH="/home/shared/subread-2.0.5-Linux-x86_64/bin/featureCounts"
        ;;
    "klone")
        HISAT2_DIR=""
        SAMTOOLS_DIR=""
        STRINGTIE_DIR=""
        GFFCOMPARE_DIR="/srlab/programs/gffcompare-0.12.6.Linux_x86_64/"
        BEDTOOLS_DIR=""
        CPC2_DIR="/srlab/programs/CPC2_standalone-1.0.1/bin/"
        CONDA_PATH="/mmfs1/gscratch/srlab/nextflow/bin/miniforge/bin/conda"
        FEATURECOUNTS_PATH=""
        ;;
    *)
        log "WARNING: Unknown environment, using RAVEN defaults"
        HISAT2_DIR="/home/shared/hisat2-2.2.1/"
        SAMTOOLS_DIR="/home/shared/samtools-1.12/"
        STRINGTIE_DIR="/home/shared/stringtie-2.2.1.Linux_x86_64/"
        GFFCOMPARE_DIR="/home/shared/gffcompare-0.12.6.Linux_x86_64/"
        BEDTOOLS_DIR="/home/shared/bedtools2/bin/"
        CPC2_DIR="/home/shared/CPC2_standalone-1.0.1/bin/"
        CONDA_PATH="/opt/anaconda/anaconda3/bin/conda"
        FEATURECOUNTS_PATH="/home/shared/subread-2.0.5-Linux-x86_64/bin/featureCounts"
        ;;
esac

# Allow manual override via environment variables
HISAT2_DIR=${HISAT2_DIR_OVERRIDE:-$HISAT2_DIR}
SAMTOOLS_DIR=${SAMTOOLS_DIR_OVERRIDE:-$SAMTOOLS_DIR}
STRINGTIE_DIR=${STRINGTIE_DIR_OVERRIDE:-$STRINGTIE_DIR}
GFFCOMPARE_DIR=${GFFCOMPARE_DIR_OVERRIDE:-$GFFCOMPARE_DIR}
BEDTOOLS_DIR=${BEDTOOLS_DIR_OVERRIDE:-$BEDTOOLS_DIR}
CPC2_DIR=${CPC2_DIR_OVERRIDE:-$CPC2_DIR}
CONDA_PATH=${CONDA_PATH_OVERRIDE:-$CONDA_PATH}
FEATURECOUNTS_PATH=${FEATURECOUNTS_PATH_OVERRIDE:-$FEATURECOUNTS_PATH}

# Error handling
handle_error() {
    log "ERROR: Command failed at line $1" "ERROR"
    exit 1
}
trap 'handle_error $LINENO' ERR

# Step tracking
should_run_step() {
    local step=$1
    [[ $step -ge $RESTART_FROM_STEP ]]
}

# File validation
validate_file() {
    local file="$1"
    local desc="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        log "Missing $desc: $file" "ERROR"
        return 1
    fi
    
    if [[ ! -s "$file" ]]; then
        log "Empty $desc: $file" "ERROR"
        return 1
    fi
    
    # Check for HTML downloads
    if head -3 "$file" 2>/dev/null | grep -qi "<!DOCTYPE\|<html>"; then
        log "HTML file detected instead of expected format: $desc" "ERROR"
        return 1
    fi
    
    return 0
}

# Download with retry
download_with_retry() {
    local url="$1"
    local output="$2"
    local desc="${3:-file}"
    local max_retries=3
    
    for attempt in $(seq 1 $max_retries); do
        log "Downloading $desc (attempt $attempt/$max_retries)"
        
        if curl -L --connect-timeout 30 --max-time 300 --retry 2 -o "$output" "$url"; then
            if validate_file "$output" "$desc"; then
                log "Successfully downloaded: $desc"
                return 0
            fi
        fi
        
        log "Download failed (attempt $attempt): $desc" "WARNING"
        [[ -f "$output" ]] && rm -f "$output"
        
        if [[ $attempt -lt $max_retries ]]; then
            sleep 5
        fi
    done
    
    log "Failed to download after $max_retries attempts: $desc" "ERROR"
    return 1
}

# Tool validation
check_tool() {
    local tool_name="$1"
    local tool_path="$2"
    
    if [[ -z "$tool_path" ]]; then
        # Try to find in PATH
        if command -v "$tool_name" &> /dev/null; then
            log "Found $tool_name in system PATH"
            return 0
        else
            log "Tool not found: $tool_name" "WARNING"
            return 1
        fi
    else
        local full_path="${tool_path}${tool_name}"
        if [[ -x "$full_path" ]]; then
            log "Found $tool_name at: $tool_path"
            return 0
        else
            log "Tool not found at specified path: $full_path" "WARNING"
            return 1
        fi
    fi
}

# Configuration summary
print_config() {
    log "Configuration Summary:"
    log "  Environment: $ENV"
    log "  Threads: $THREADS"
    log "  Data Directory: $DATA_DIR"
    log "  Output Directory: $OUTPUT_DIR"
    log "  Log Directory: $LOG_DIR"
    log "  Restart from step: $RESTART_FROM_STEP"
    log "  Min transcript length: $MIN_TRANSCRIPT_LENGTH"
    log "  Min coverage: $MIN_COVERAGE"
    log "  Min sample fraction: $MIN_SAMPLE_FRACTION"
}

# Main pipeline function
main() {
    log "Starting robust lncRNA discovery pipeline"
    print_config
    
    # Create directories
    mkdir -p "$DATA_DIR" "$OUTPUT_DIR" "$LOG_DIR" "$FASTQ_DIR"
    
    # Validate critical tools
    local tools_ok=true
    check_tool "hisat2" "$HISAT2_DIR" || tools_ok=false
    check_tool "samtools" "$SAMTOOLS_DIR" || tools_ok=false
    check_tool "stringtie" "$STRINGTIE_DIR" || tools_ok=false
    check_tool "bedtools" "$BEDTOOLS_DIR" || tools_ok=false
    check_tool "python" "" || tools_ok=false
    
    if [[ "$tools_ok" == "false" ]]; then
        log "Some critical tools are missing. Please install them or update paths." "ERROR"
        log "You can override tool paths using environment variables like HISAT2_DIR_OVERRIDE" "INFO"
        exit 1
    fi
    
    # Step 1: Download data
    if should_run_step 1; then
        log "Step 1: Downloading reference data"
        
        # Download FASTQ files
        if [[ ! -d "$FASTQ_DIR" ]] || [[ -z "$(ls -A "$FASTQ_DIR" 2>/dev/null)" ]]; then
            log "Downloading FASTQ files..."
            wget -nv -r --no-directories --no-parent -P "$FASTQ_DIR" -A "*$FASTQ_SUFFIX" "$FASTQ_SOURCE" > "$FASTQ_DIR/wget.log" 2>&1 || true
            
            # Check if any files were downloaded
            if [[ -z "$(ls -A "$FASTQ_DIR" 2>/dev/null | grep "$FASTQ_SUFFIX")" ]]; then
                log "No FASTQ files downloaded - continuing anyway" "WARNING"
            else
                log "FASTQ files downloaded successfully"
            fi
        else
            log "FASTQ files already exist, skipping download"
        fi
        
        # Download genome files
        download_with_retry "$GENOME_SOURCE" "$GENOME_FASTA" "genome FASTA"
        download_with_retry "$GTF_SOURCE" "$GENOME_GTF" "genome GTF"
        download_with_retry "$GFF_SOURCE" "$GENOME_GFF" "genome GFF"
        
        log "Step 1 completed"
    fi
    
    # Step 2: HISAT2 alignment
    if should_run_step 2; then
        log "Step 2: HISAT2 alignment"
        
        # Build index if needed
        if [[ ! -f "${GENOME_INDEX}.1.ht2" ]]; then
            log "Building HISAT2 index..."
            "${HISAT2_DIR}hisat2_extract_exons.py" "$GENOME_GTF" > "$OUTPUT_DIR/exon.txt"
            "${HISAT2_DIR}hisat2_extract_splice_sites.py" "$GENOME_GTF" > "$OUTPUT_DIR/splice_sites.txt"
            
            "${HISAT2_DIR}hisat2-build" -p "$THREADS" "$GENOME_FASTA" "$GENOME_INDEX" \
                --exon "$OUTPUT_DIR/exon.txt" --ss "$OUTPUT_DIR/splice_sites.txt" \
                2> "$OUTPUT_DIR/hisat2-build_stats.txt"
        else
            log "HISAT2 index already exists, skipping build"
        fi
        
        # Align reads
        cd "$FASTQ_DIR"
        for r2_file in *_R2_*."$FASTQ_SUFFIX"; do
            [[ ! -f "$r2_file" ]] && continue
            
            sample=$(basename "$r2_file" | sed "s/_R2_.*//" )
            r1_file=$(echo "$r2_file" | sed "s/_R2_/_R1_/")
            sam_output="$OUTPUT_DIR/${sample}.sam"
            
            [[ ! -f "$r1_file" ]] && { log "Missing R1 for $sample" "WARNING"; continue; }
            [[ -f "$sam_output" ]] && { log "Skipping existing alignment: $sample"; continue; }
            
            log "Aligning sample: $sample"
            "${HISAT2_DIR}hisat2" -x "$GENOME_INDEX" -p "$THREADS" \
                -1 "$r1_file" -2 "$r2_file" -S "$sam_output"
        done
        
        log "Step 2 completed"
    fi
    
    # Step 3: SAM to BAM conversion
    if should_run_step 3; then
        log "Step 3: Converting SAM to sorted BAM"
        
        cd "$OUTPUT_DIR"
        for sam_file in *.sam; do
            [[ ! -f "$sam_file" ]] && continue
            
            sample=$(basename "$sam_file" .sam)
            bam_file="${sample}.bam"
            sorted_bam="${sample}.sorted.bam"
            
            [[ -f "$sorted_bam" ]] && { log "Skipping existing BAM: $sample"; continue; }
            
            log "Converting SAM to BAM: $sample"
            "${SAMTOOLS_DIR}samtools" view -bS -@ "$THREADS" "$sam_file" > "$bam_file"
            "${SAMTOOLS_DIR}samtools" sort -@ "$THREADS" "$bam_file" -o "$sorted_bam"
            "${SAMTOOLS_DIR}samtools" index -@ "$THREADS" "$sorted_bam"
            
            rm -f "$sam_file" "$bam_file"
        done
        
        log "Step 3 completed"
    fi
    
    # Step 4: StringTie assembly
    if should_run_step 4; then
        log "Step 4: StringTie transcript assembly"
        
        cd "$OUTPUT_DIR"
        
        # Individual assemblies
        for bam_file in *.sorted.bam; do
            [[ ! -f "$bam_file" ]] && continue
            
            sample=$(basename "$bam_file" .sorted.bam)
            gtf_output="${sample}.gtf"
            
            [[ -f "$gtf_output" ]] && { log "Skipping existing assembly: $sample"; continue; }
            
            log "Assembling transcripts: $sample"
            "${STRINGTIE_DIR}stringtie" -p "$THREADS" -G "$GENOME_GFF" \
                -o "$gtf_output" "$bam_file"
        done
        
        # Merge assemblies
        if [[ ! -f "stringtie_merged.gtf" ]]; then
            log "Merging StringTie assemblies..."
            "${STRINGTIE_DIR}stringtie" --merge -G "$GENOME_GFF" \
                -o "stringtie_merged.gtf" *.gtf
        else
            log "Merged GTF already exists, skipping merge"
        fi
        
        log "Step 4 completed"
    fi
    
    # Step 5: GFFCompare and filtering
    if should_run_step 5; then
        log "Step 5: GFFCompare and lncRNA candidate filtering"
        
        cd "$OUTPUT_DIR"
        
        # GFFCompare
        if [[ ! -f "gffcompare_merged.annotated.gtf" ]]; then
            log "Running GFFCompare..."
            "${GFFCOMPARE_DIR}gffcompare" -r "$GENOME_GFF" \
                -o "gffcompare_merged" "stringtie_merged.gtf"
        else
            log "GFFCompare results already exist, skipping"
        fi
        
        # Filter lncRNA candidates
        if [[ ! -f "lncRNA_candidates.gtf" ]]; then
            log "Filtering lncRNA candidates..."
            awk '$3 == "transcript" && $1 !~ /^#/' "gffcompare_merged.annotated.gtf" | \
            grep -E "$GFFPATTERN" | \
            awk '($5 - $4 > '"$MIN_TRANSCRIPT_LENGTH"') || ($4 - $5 > '"$MIN_TRANSCRIPT_LENGTH"')' \
                > "lncRNA_candidates.gtf"
        else
            log "lncRNA candidates already filtered, skipping"
        fi
        
        # Extract sequences
        if [[ ! -f "lncRNA_candidates.fasta" ]]; then
            log "Extracting candidate sequences..."
            "${BEDTOOLS_DIR}bedtools" getfasta -fi "$GENOME_FASTA" \
                -bed "lncRNA_candidates.gtf" -fo "lncRNA_candidates.fasta" -name -split
        else
            log "Candidate sequences already extracted, skipping"
        fi
        
        log "Step 5 completed"
    fi
    
    # Step 6: CPC2 analysis
    if should_run_step 6; then
        log "Step 6: CPC2 coding potential analysis"
        
        cd "$OUTPUT_DIR"
        
        if [[ ! -f "CPC2.txt" ]]; then
            log "Running CPC2 analysis..."
            if command -v conda &> /dev/null || [[ -f "$CONDA_PATH" ]]; then
                if [[ -f "$CONDA_PATH" ]]; then
                    eval "$("$CONDA_PATH" shell.bash hook)"
                fi
            fi
            python "${CPC2_DIR}CPC2.py" -i "lncRNA_candidates.fasta" -o "CPC2"
        else
            log "CPC2 analysis already completed, skipping"
        fi
        
        # Filter noncoding transcripts
        if [[ ! -f "noncoding_transcripts_ids.txt" ]]; then
            log "Filtering noncoding transcripts..."
            awk '$8 == "noncoding" {print $1}' "CPC2.txt" > "noncoding_transcripts_ids.txt"
        else
            log "Noncoding transcripts already filtered, skipping"
        fi
        
        log "Step 6 completed"
    fi
    
    # Step 7: Final lncRNA processing
    if should_run_step 7; then
        log "Step 7: Final lncRNA processing"
        
        cd "$OUTPUT_DIR"
        
        # Subset fasta
        if [[ ! -f "lncRNA.fasta" ]]; then
            log "Creating final lncRNA FASTA..."
            "${SAMTOOLS_DIR}samtools" faidx "lncRNA_candidates.fasta" \
                -r "noncoding_transcripts_ids.txt" > "lncRNA.fasta"
        else
            log "Final lncRNA FASTA already exists, skipping"
        fi
        
        # Create BED file
        if [[ ! -f "lncRNA.bed" ]]; then
            log "Creating lncRNA BED file..."
            while IFS= read -r line; do
                line="${line//transcript::/}"
                IFS=':' read -r chromosome pos <<< "$line"
                IFS='-' read -r start end <<< "$pos"
                start=$((start + 1))
                printf "%s\t%s\t%s\n" "$chromosome" "$start" "$end"
            done < "noncoding_transcripts_ids.txt" > "lncRNA.bed"
        else
            log "lncRNA BED file already exists, skipping"
        fi
        
        # Create final GTF
        if [[ ! -f "lncRNA.gtf" ]]; then
            log "Creating final lncRNA GTF..."
            awk 'BEGIN{OFS="\t"; count=1} {printf "%s\t.\tlncRNA\t%d\t%d\t.\t+\t.\tgene_id \"lncRNA_%03d\";\n", $1, $2, $3, count++;}' \
                "lncRNA.bed" > "lncRNA.gtf"
        else
            log "Final lncRNA GTF already exists, skipping"
        fi
        
        # Remove duplicates
        log "Removing duplicates..."
        awk '!seen[$1,$4,$5]++' "lncRNA.gtf" > "lncRNA.gtf.tmp" && mv "lncRNA.gtf.tmp" "lncRNA.gtf"
        
        log "Step 7 completed"
    fi
    
    # Step 8: Count matrix (optional)
    if should_run_step 8; then
        log "Step 8: Generating count matrix"
        
        matrix_dir="../output/13-Peve-lncRNA-matrix"
        mkdir -p "$matrix_dir"
        
        if [[ ! -f "$matrix_dir/Peve_lncRNA_counts.txt" ]] && [[ -n "$FEATURECOUNTS_PATH" ]] && [[ -x "$FEATURECOUNTS_PATH" ]]; then
            log "Running featureCounts..."
            "$FEATURECOUNTS_PATH" -T "$THREADS" -O --fraction \
                -a "$OUTPUT_DIR/lncRNA.gtf" \
                -o "$matrix_dir/Peve_lncRNA_counts.txt" \
                -t lncRNA -g gene_id -p \
                "$OUTPUT_DIR"/*.sorted.bam
        else
            log "Skipping featureCounts (tool not available or output exists)"
        fi
        
        # Clean sample names
        if [[ -f "$matrix_dir/Peve_lncRNA_counts.txt" ]] && [[ ! -f "$matrix_dir/Peve_lncRNA_counts.clean.txt" ]]; then
            log "Cleaning count matrix..."
            awk 'BEGIN{FS=OFS="\t"} /^Geneid/ {for(i=7;i<=NF;i++) {gsub(/^.*\//, "", $i); sub(/\.sorted\.bam$/, "", $i)}} {print}' \
                "$matrix_dir/Peve_lncRNA_counts.txt" > "$matrix_dir/Peve_lncRNA_counts.clean.txt"
        fi
        
        # Filter count matrix
        if [[ -f "$matrix_dir/Peve_lncRNA_counts.clean.txt" ]] && [[ ! -f "$matrix_dir/Peve_lncRNA_counts_filtered.txt" ]]; then
            log "Filtering count matrix..."
            if [[ -f "$SCRIPT_DIR/13.1-filter_count_matrix.py" ]]; then
                python "$SCRIPT_DIR/13.1-filter_count_matrix.py" \
                    "$matrix_dir/Peve_lncRNA_counts.clean.txt" \
                    "$matrix_dir/Peve_lncRNA_counts_filtered.txt" \
                    --min-coverage "$MIN_COVERAGE" \
                    --min-sample-fraction "$MIN_SAMPLE_FRACTION"
            else
                log "Count matrix filter script not found, skipping filtering" "WARNING"
            fi
        fi
        
        log "Step 8 completed"
    fi
    
    log "Pipeline completed successfully!"
    
    # Generate summary statistics
    if [[ -f "$OUTPUT_DIR/lncRNA.gtf" ]]; then
        log "Final lncRNA statistics:"
        awk '{count++; key=$1 FS $4 FS $5; seen[key]++; len=$5-$4+1; if(min=="" || len<min) min=len; if(len>max) max=len; sum+=len} END {print "Total entries:", count; print "Unique genes:", length(seen); print "Min length:", min; print "Max length:", max; print "Average length:", sum/count}' "$OUTPUT_DIR/lncRNA.gtf" | while read line; do log "$line"; done
    else
        log "No final lncRNA GTF file found" "WARNING"
    fi
}

# Help function
show_help() {
    cat << EOF
Robust lncRNA Discovery Pipeline

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -t, --threads N         Number of threads to use (default: $DEFAULT_THREADS)
    -s, --restart-step N    Restart from step N (default: 1)
    --data-dir DIR          Data directory (default: $DEFAULT_DATA_DIR)
    --output-dir DIR        Output directory (default: $DEFAULT_OUTPUT_DIR)
    --log-dir DIR           Log directory (default: $DEFAULT_LOG_DIR)

Environment Variables:
    You can override tool paths using these variables:
    HISAT2_DIR_OVERRIDE, SAMTOOLS_DIR_OVERRIDE, STRINGTIE_DIR_OVERRIDE,
    GFFCOMPARE_DIR_OVERRIDE, BEDTOOLS_DIR_OVERRIDE, CPC2_DIR_OVERRIDE,
    CONDA_PATH_OVERRIDE, FEATURECOUNTS_PATH_OVERRIDE

Examples:
    # Run complete pipeline
    $0
    
    # Run with 16 threads
    $0 --threads 16
    
    # Restart from step 5
    $0 --restart-step 5
    
    # Use custom tool path
    HISAT2_DIR_OVERRIDE="/custom/path/to/hisat2/" $0

Pipeline Steps:
    1. Download reference data
    2. HISAT2 alignment
    3. SAM to BAM conversion
    4. StringTie assembly
    5. GFFCompare and filtering
    6. CPC2 analysis
    7. Final lncRNA processing
    8. Count matrix generation

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -s|--restart-step)
            RESTART_FROM_STEP="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        *)
            log "Unknown option: $1" "ERROR"
            show_help
            exit 1
            ;;
    esac
done

# Run main pipeline
main "$@"