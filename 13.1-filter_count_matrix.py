#!/usr/bin/env python3
"""
Filter count matrix to remove genes with low expression.
Removes lines with less than 10x coverage on half of the samples.

Usage:
    python 13.1-filter_count_matrix.py input_file output_file

Author: lncRNA Discovery Workflow
"""

import sys
import argparse


def filter_count_matrix(input_file, output_file, min_coverage=10, min_sample_fraction=0.5):
    """
    Filter count matrix to remove genes with low expression.
    
    Parameters:
    - input_file: Path to input count matrix file
    - output_file: Path to output filtered count matrix file
    - min_coverage: Minimum coverage threshold (default: 10)
    - min_sample_fraction: Minimum fraction of samples that must meet threshold (default: 0.5)
    """
    try:
        with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
            header = infile.readline()
            outfile.write(header)
            
            # Parse header to determine number of sample columns
            # Format: Geneid	Chr	Start	End	Strand	Length	Sample1	Sample2	...
            header_parts = header.strip().split('\t')
            sample_start_idx = 6  # Sample columns start at index 6
            total_samples = len(header_parts) - sample_start_idx
            min_samples_required = int(total_samples * min_sample_fraction)
            
            print(f"Total samples: {total_samples}")
            print(f"Minimum samples required to meet threshold: {min_samples_required}")
            print(f"Coverage threshold: {min_coverage}")
            
            kept_genes = 0
            total_genes = 0
            
            for line in infile:
                total_genes += 1
                parts = line.strip().split('\t')
                
                if len(parts) < sample_start_idx:
                    # Skip malformed lines
                    continue
                
                # Count samples meeting coverage threshold
                samples_above_threshold = 0
                for i in range(sample_start_idx, len(parts)):
                    try:
                        count = float(parts[i])
                        if count >= min_coverage:
                            samples_above_threshold += 1
                    except (ValueError, IndexError):
                        # Skip invalid values
                        continue
                
                # Keep gene if enough samples meet threshold
                if samples_above_threshold >= min_samples_required:
                    outfile.write(line)
                    kept_genes += 1
            
            print(f"Genes processed: {total_genes}")
            print(f"Genes kept: {kept_genes}")
            print(f"Genes filtered out: {total_genes - kept_genes}")
            print(f"Filtering completed successfully!")
            
    except FileNotFoundError as e:
        print(f"Error: Input file '{input_file}' not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error processing files: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Filter count matrix to remove genes with low expression"
    )
    parser.add_argument(
        "input_file", 
        help="Input count matrix file"
    )
    parser.add_argument(
        "output_file", 
        help="Output filtered count matrix file"
    )
    parser.add_argument(
        "--min-coverage", 
        type=int, 
        default=10,
        help="Minimum coverage threshold (default: 10)"
    )
    parser.add_argument(
        "--min-sample-fraction", 
        type=float, 
        default=0.5,
        help="Minimum fraction of samples that must meet threshold (default: 0.5)"
    )
    
    args = parser.parse_args()
    
    # Validate inputs
    if args.min_coverage < 0:
        print("Error: Minimum coverage must be non-negative")
        sys.exit(1)
    
    if not (0 <= args.min_sample_fraction <= 1):
        print("Error: Minimum sample fraction must be between 0 and 1")
        sys.exit(1)
    
    filter_count_matrix(
        args.input_file, 
        args.output_file, 
        args.min_coverage, 
        args.min_sample_fraction
    )


if __name__ == "__main__":
    main()