# ctg-sc-atac-10x 
## Nextflow pipeline for preprocessing of 10x chromium sc-ATAC data with cellranger. 

- Designed to handle multiple projects in one sequencing run (but also works with only one project)
- Supports mm10 and hg38 references, but can also be run with custom reference genome and annotation (must be added via nextflow.config). See custom genome below.
- Supports nuclei samples

## USAGE

1. Clone and build the Singularity container for this pipeline: https://github.com/perllb/ctg-sc-atac-10x/tree/master/container/ctg-sc-atac-10x
2. Edit your samplesheet to match the example samplesheet. See section `SampleSheet` below
3. Edit the nextflow.config file to fit your project and system. 
4. Run pipeline 
```
nohup nextflow run pipe-sc-atac-10x.nf > log.pipe-sc-atac-10x.txt &
```

## Input files

1. Samplesheet (`CTG_SampleSheet.sc-atac-10x.csv`)

### Samplesheet requirements:

Note: no header! only the rows shown below, starting with the column names.
Note: Must be in comma-separated values format (.csv)

 | Sample_ID | index | Sample_Project | Sample_Species | 
 | --- | --- | --- | --- | 
 | Si1 | SI-GA-D9 | 2021_012 | human | 
 | Si2 | SI-GA-H9 | 2021_012 | human | 
 | Sample1 | SI-GA-C9 | 2021_013 | mouse | 
 | Sample2 | SI-GA-C9 | 2021_013 | mouse |

#### The nf-pipeline takes the following Columns from samplesheet to use in channels:
- `Sample_ID` : ID of sample. Sample_ID can only contain a-z, A-Z and "_".  E.g space and hyphen ("-") are not allowed! If 'Sample_Name' is present, it will be ignored. 
- `index` : Must use index ID (10x ID) if dual index. For single index, the index sequence works too.
- `Sample_Project` : Project ID. E.g. 2021_033, 2021_192.
- `Sample_Species` : Only 'human'/'mouse'/'custom' are accepted. If species is not human or mouse, set 'custom'. This custom reference genome has to be specified in the nextflow config file. See below how to edit the config file.

### Samplesheet template

- Samplesheet name `CTG_SampleSheet.sc-atac-10x.csv`
```
Sample_ID,index,Sample_Project,Sample_Species 
Si1,Sn1,SI-GA-D9,2021_012,human 
Si2,Sn2,SI-GA-H9,2021_012,human 
Sample1,S1,SI-GA-C9,2021_013,mouse 
Sample2,S23,SI-GA-C9,2021_013,mouse
``` 

## Pipeline steps:

Cellranger version: cellranger atac v2.0.0 

* `Demultiplexing` (cellranger mkfastq): Converts raw basecalls to fastq, and demultiplex samples based on index (https://support.10xgenomics.com/single-cell-atac/software/pipelines/latest/using/mkfastq).
* `FastQC`: FastQC calculates quality metrics on raw sequencing reads (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/). MultiQC summarizes FastQC reports into one document (https://multiqc.info/).
* `Align` + `Counts` (cellranger count): Aligns fastq files to reference genome, counts genes for each cell/barcode, perform secondary analysis such as clustering and generates the cloupe files (https://support.10xgenomics.com/single-cell-atac/software/pipelines/latest/using/count).
* `Aggregation` (cellranger aggr): Automatically creates the input csv pointing to molecule_info.h5 files for each sample to be aggregated and executes aggregation (https://support.10xgenomics.com/single-cell-atac/software/pipelines/latest/using/aggr). This is only run if there is more than one sample pr project.
* `Cellranger count metrics` (bin/ctg-sc-count-metrics-concat.py): Collects main count metrics (#cells and #reads/cell etc.) from each sample and collect in table
* `multiQC`: Compile fastQC and cellranger count metrics in multiqc report
* `md5sum`: md5sum of all generated files


## Output:
* ctg-PROJ_ID-output
    * `qc`: Quality control output. 
        * cellranger metrics: Main metrics summarising the count / cell output 
        * fastqc output (https://www.bioinformatics.babraham.ac.uk/projects/fastqc/)
        * multiqc output: Summarizing FastQC output and demultiplexing (https://multiqc.info/)
    * `fastq`: Contains raw fastq files from cellranger mkfastq.
    * `count-cr`: Cellranger count output. Here you find gene/cell count matrices, secondary analysis output, and more. See (https://support.10xgenomics.com/single-cell-atac/software/pipelines/latest/using/count) for more information on the output files.
    * `summaries`: 
        * web-summary files which provide an overview of essential metrics from the 10x run. 
        * cloupe files which can be used to explore the data interactively in the Loupe browser (https://support.10xgenomics.com/single-cell-atac/software/visualization/latest/what-is-loupe-cell-browser)  
    * `aggregate`:
        * Output from cellranger aggregation. This is only run if there is more than one sample pr project.
    * `ctg-md5.PROJ_ID.txt`: text file with md5sum recursively from output dir root    





## Container


## Custom genome 

If custom genome (not hg38 or mm10) is used

1. Set "Sample_Species" column to 'custom' in samplesheet:

Example:
 | Sample_ID | Sample_Name | index | Sample_Project | Sample_Species | 
 | --- | --- | --- | --- | --- | 
 | Si1 | Sn1 | SI-GA-D9 | proj_2021_012 | **custom** | 
 | Si2 | Sn2 | SI-GA-H9 | proj_2021_012 | **custom** | 
 
 2. In nextflow.config, set 
 `custom_genome=/PATH/TO/CUSTOMGENOME`
 
### Add custom genes (e.g. reporters) to cellranger annotation

You can use this script to add custom genes to the cellranger ref
https://github.com/perllb/ctg-cellranger-add2ref


## Dependencies
- nextflow version 19.04.1.5072
- Singularity (v 3.7.0-1.el7)
- java (openjdk version "10.0.2" 2018-07-17)
- OpenJDK Runtime Environment Zulu10.3+5 (build 10.0.2+13)
- OpenJDK 64-Bit Server VM Zulu10.3+5 (build 10.0.2+13, mixed mode)
- Singularity container (https://github.com/perllb/ctg-sc-atac-10x/blob/main/container/Singularity_sc-atac-10x-builder)
- Cellranger 10x ATAC or ARC references (e.g. refdata-cellranger-arc-GRCh38-2020-A-2.0.0 and refdata-cellranger-arc-mm10-2020-A-2.0.0)
