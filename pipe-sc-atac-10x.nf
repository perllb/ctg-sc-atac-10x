#!/usr/bin/env nextFlow

// Base params
runfolder = params.runfolder
basedir = params.basedir
metaid = params.metaid

// Output dirs
outdir = params.outdir
fqdir = params.fqdir
ctgqc = params.ctgqc

// Demux args
b2farg = params.bcl2fastqarg
index = params.index
demux = params.demux

// Read and process CTG samplesheet 
sheet = file(params.sheet)

// create new samplesheet in cellranger mkfastq IEM (--samplesheet) format. This will be used only for demultiplexing
newsheet = "$basedir/samplesheet.nf.sc-atac-10x.csv"

println "============================="
println ">>> sc-atac-10x pipeline for multiple projects / run >>>"
println ""
println "> INPUT: "
println ""
println "> runfolder		: $runfolder "
println "> sample-sheet		: $sheet "
println "> run-meta-id		: $metaid "
println "> basedir		: $basedir "
println ""
println " - demultiplexing arguments "
println "> bcl2fastq-arg        : '${b2farg}' "
println "> demux                : $demux " 
println "> index                : $index "
println ""
println "> - output directories "
println "> output-dir           : $outdir "
println "> fastq-dir            : $fqdir "
println "> ctg-qc-dir           : $ctgqc "
println "============================="


// all samplesheet info
Channel
    .fromPath(sheet)
    .splitCsv(header:true)
    .map { row -> tuple( row.Sample_ID, row.Sample_Project, row.Sample_Species) }
    .tap{infoall}
    .into { crCount_csv; cragg_ch; mvfastq_csv }

// Projects
Channel
    .fromPath(sheet)
    .splitCsv(header:true)
    .map { row -> row.Sample_Project }
    .unique()
    .tap{infoProject}
    .into { count_summarize; mqc_cha_init_uniq }


// Channel to start count if demux == 'n'
if ( demux == 'n' ) {
   Channel
	 .from("1")
    	 .set{ crCount }
}

println " > Samples to process: "
println "[Sample_ID,Sample_Name,Sample_Project,Sample_Species,agg]"
infoall.subscribe { println "Info: $it" }

println " > Projects to process : "
println "[Sample_Project]"
infoProject.subscribe { println "Info Projects: $it" }

// Parse samplesheet
process parsesheet {

	tag "$metaid"

	input:
	val sheet
	val index

	output:
	val newsheet into demux_sheet

	when:
	demux == 'y'

	"""
python $basedir/bin/ctg-parse-samplesheet.10x.py -s $sheet -o $newsheet -i $index
	"""
}

	

// Run mkFastq
process mkfastq {

	tag "$metaid"

	input:
        val sheet from demux_sheet

	output:
	val 1 into moveFastq

	when:
	demux == 'y'

	"""
cellranger-atac mkfastq \\
	   --id=$metaid \\
	   --run=$runfolder \\
	   --samplesheet=$sheet \\
	   --jobmode=local \\
	   --localmem=100 \\
	   --output-dir $fqdir \\
	   $b2farg
"""

}

process moveFastq {

    tag "${sid}-${projid}"

    input:
    val x from moveFastq
    set sid, projid, ref from mvfastq_csv

    output:
    val "y" into crCount
    set sid, projid, ref into fqc_ch

    when:
    demux = 'y'

    """
    mkdir -p ${outdir}/${projid}
    mkdir -p ${outdir}/${projid}/fastq

    mkdir -p ${outdir}/${projid}/fastq/$sid

    if [ -d ${fqdir}/${projid}/$sid ]; then
        mv ${fqdir}/${projid}/$sid ${outdir}/${projid}/fastq/
    else
	mv ${fqdir}/${projid}/$sid* ${outdir}/${projid}/fastq/$sid/
    fi
    """

}

process count {

	tag "${sid}-${projid}"
	publishDir "${outdir}/${projid}/count-cr/", mode: "copy", overwrite: true

	input: 
	val sheet
	val y from crCount.collect()
        set sid, projid, ref from crCount_csv

	output:
        file "${sid}/outs/" into samplename
        val "${projid}/qc/cellranger/${sid}.metrics_summary.csv" into count_metrics
	set val("${outdir}/${projid}/aggregate/${sid}.fragments.tsv.gz"), val("${outdir}/${projid}/aggregate/${sid}.singlecell.csv") into count_agg


	"""
        if [ $ref == "Human" ] || [ $ref == "human" ]
        then
            genome=$params.human
        elif [ $ref == "mouse" ] || [ $ref == "Mouse" ]
        then
            genome=$params.mouse
        elif [ $ref == "custom"  ] || [ $ref == "Custom" ] 
        then
            genome=${params.custom_genome}
        else
            echo ">SPECIES NOT RECOGNIZED!"
            genome="ERR"
        fi

        mkdir -p ${outdir}/${projid}/count-cr/


	cellranger-atac count \\
	     --id=$sid \\
	     --fastqs=${outdir}/$projid/fastq/$sid \\
	     --sample=$sid \\
             --project=$projid \\
	     --reference=\$genome \\
             --localcores=19 --localmem=110

        mkdir -p ${outdir}
        mkdir -p ${outdir}/${projid}
        mkdir -p ${outdir}/${projid}/summaries
        mkdir -p ${outdir}/${projid}/summaries/cloupe
        mkdir -p ${outdir}/${projid}/summaries/web-summaries

	mkdir -p ${ctgqc}/${projid}
	mkdir -p ${ctgqc}/${projid}/web-summaries

	## Copy h5 file for aggregation
	aggdir=$outdir/$projid/aggregate
	mkdir -p \$aggdir
	cp ${sid}/outs/fragments.tsv.gz ${outdir}/${projid}/aggregate/${sid}.fragments.tsv.gz
	cp ${sid}/outs/singlecell.csv ${outdir}/${projid}/aggregate/${sid}.singlecell.csv

	## Copy metrics file for qc
	# Remove if it exists
	if [ -f ${outdir}/${projid}/qc/cellranger/${sid}.summary.csv ]; then
	    rm -r ${outdir}/${projid}/qc/cellranger/${sid}.summary.csv
	fi
	mkdir -p ${outdir}/${projid}/qc/
	mkdir -p ${outdir}/${projid}/qc/cellranger/

        cp ${sid}/outs/summary.csv ${outdir}/${projid}/qc/cellranger/${sid}.summary.csv

	## Copy to delivery folder 
        cp ${sid}/outs/web_summary.html ${outdir}/${projid}/summaries/web-summaries/${sid}.web_summary.html
        cp ${sid}/outs/cloupe.cloupe ${outdir}/${projid}/summaries/cloupe/${sid}_cloupe.cloupe

	## Copy to CTG QC dir 
        cp ${sid}/outs/web_summary.html ${ctgqc}/${projid}/web-summaries/${sid}.web_summary.html

	"""

}

process fastqc {

	tag "${sid}-${projid}"

	input:
	set sid, projid, ref from fqc_ch	
        
        output:
        val projid into mqc_cha
	val "x" into mqc_cha_init

	"""

        mkdir -p ${outdir}/${projid}/qc
        mkdir -p ${outdir}/${projid}/qc/fastqc

        for file in ${outdir}/${projid}/fastq/${sid}/*fastq.gz
            do fastqc -t ${task.cpus} \$file --outdir=${outdir}/${projid}/qc/fastqc
        done
	"""
    
}

process summarize_count {

	tag "${projid}"

	input:
	val metrics from count_metrics.collect()
	val projid from count_summarize 

	output:
	val projid into mqc_count 	
	val "x" into run_summarize

	"""

	cd $outdir/$projid
	mkdir -p ${outdir}/${projid}/
	mkdir -p ${outdir}/${projid}/qc
	mkdir -p ${outdir}/${projid}/qc/cellranger
	
	python $basedir/bin/ctg-sc-atac-count-metrics-concat.py -i ${outdir}/${projid}/ -o ${outdir}/${projid}/qc/cellranger

	# Copy to summaries delivery folder
	cp ${outdir}/${projid}/qc/cellranger/ctg-cellranger-atac-count-summary_metrics.csv ${outdir}/${projid}/summaries/web-summaries/
	"""
}
	
// Project specific multiqc 
process multiqc {

    tag "${projid}"

    input:
    set projid, projid2 from mqc_cha.unique().phase(mqc_count.unique())

    output:
    val projid into multiqc_outch

    script:
    """
    
    cd $outdir/$projid
    multiqc -f ${outdir}/$projid  --outdir ${outdir}/$projid/qc/multiqc/ -n ${projid}_multiqc_report.html

    mkdir -p ${ctgqc}
    mkdir -p ${ctgqc}/$projid

    cp -r ${outdir}/$projid/qc ${ctgqc}/$projid/

    """
}

process multiqc_count_run {

    tag "${metaid}"

    input:
    val x from run_summarize.collect()
        
    output:
    val "x" into summarized

    """
    cd $outdir 
    multiqc -f ${fqdir} ${outdir}/*/qc/cellranger/ --outdir ${ctgqc} -n ${metaid}_run_sc-atac-10x_summary_multiqc_report.html

    """

}

// aggregation
process gen_aggCSV {

    tag "${sid}_${projid}"

    input:
    set sid, projid, ref from cragg_ch

    output:
    set projid, ref into craggregate

    """
    aggdir=$outdir/$projid/aggregate
    mkdir -p \$aggdir
    aggcsv=\$aggdir/${projid}_libraries.csv
    if [ -f \$aggcsv ]
    then
        if grep -q $sid \$aggcsv
        then
             echo ""
        else
             echo "${sid},${outdir}/${projid}/aggregate/${sid}.fragments.tsv.gz,${outdir}/${projid}/aggregate/${sid}.singlecell.csv" >> \$aggcsv
        fi
    else
        echo "library_id,fragments,cells" > \$aggcsv
	echo "${sid},${outdir}/${projid}/aggregate/${sid}.fragments.tsv.gz,${outdir}/${projid}/aggregate/${sid}.singlecell.csv" >> \$aggcsv
    fi

    """
}

process aggregate {

    publishDir "${outdir}/${projid}/aggregate/", mode: 'move', overwrite: true
    tag "$projid"
  
    input:
    set projid, ref from craggregate.unique()
    set fragments, singlecell from count_agg.collect()

    output:
    file "${projid}_agg/outs" into doneagg
    val projid into md5_proj
    val "x" into md5_wait


    """
    if [ $ref == "Human" ] || [ $ref == "human" ]
    then
        genome=$params.human
    elif [ $ref == "mouse" ] || [ $ref == "Mouse" ]
    then
        genome=$params.mouse
    elif [ $ref == "custom"  ] || [ $ref == "Custom" ] 
    then
        genome=${params.custom_genome}
    else
        echo ">SPECIES NOT RECOGNIZED!"
        genome="ERR"
    fi

    aggdir="$outdir/$projid/aggregate"

    cellranger-atac aggr \
       --id ${projid}_agg \
       --csv \${aggdir}/${projid}_libraries.csv \
       --normalize depth
       --reference \$genome

    ## Copy to delivery folder 
    cp ${projid}_agg/outs/web_summary.html ${outdir}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html
    cp ${projid}_agg/outs/count/cloupe.cloupe ${outdir}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe
    
    ## Copy to CTG QC dir 
    cp ${outdir}/${projid}/summaries/web-summaries/${projid}_agg.web_summary.html ${ctgqc}/${projid}/web-summaries/
    cp ${outdir}/${projid}/summaries/cloupe/${projid}_agg_cloupe.cloupe ${ctgqc}/${projid}/web-summaries/

    ## Remove the molecule_info.h5 files that are stored in the aggregate folder (the original files are still in count-cr/../outs 
    rm ${outdir}/${projid}/aggregate/*tsv.gz
    rm ${outdir}/${projid}/aggregate/*singlecell.csv

    """

}

process md5sum {

	input:
	val projid from md5_proj.unique()
	val x from md5_wait.collect()
	
	"""
	cd ${outdir}/${projid}/
	find -type f -exec md5sum '{}' \\; > ctg-md5.${projid}.txt
        """ 

}