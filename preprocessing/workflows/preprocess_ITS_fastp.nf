#!/usr/bin/env nextflow

nextflow.enable.dsl=2

params.input_dir = null
params.outdir = "preprocessing/results/ITS_fastp"
params.pattern = "*_R{1,2}.fastq.gz"

params.fastp_container = "/home/FCAM/covando/ecotourism-microbiome/containers/fastp/0.24.0/fastp_0.24.0.sif"
params.fastp_threads = 4
params.cut_window_size = 4
params.cut_mean_quality = 20
params.cut_front = true
params.cut_tail = true
params.detect_adapter_for_pe = true

process FASTP_ITS {

    tag "$sample_id"

    cpus params.fastp_threads
    container params.fastp_container

    publishDir "${params.outdir}/fastq_trimmed", mode: 'copy', pattern: "*.fastq.gz"
    publishDir "${params.outdir}/fastp_reports", mode: 'copy', pattern: "*.{html,json}"

    input:
    tuple val(sample_id), path(read1), path(read2)

    output:
    tuple val(sample_id), path("${sample_id}_fastp_R1.fastq.gz"), path("${sample_id}_fastp_R2.fastq.gz")
    path "${sample_id}.fastp.html"
    path "${sample_id}.fastp.json"

    script:
    def cut_front_opt = params.cut_front ? "--cut_front" : ""
    def cut_tail_opt = params.cut_tail ? "--cut_tail" : ""
    def adapter_opt = params.detect_adapter_for_pe ? "--detect_adapter_for_pe" : ""

    """
    fastp \
      -i ${read1} \
      -I ${read2} \
      -o ${sample_id}_fastp_R1.fastq.gz \
      -O ${sample_id}_fastp_R2.fastq.gz \
      ${cut_front_opt} \
      ${cut_tail_opt} \
      --cut_window_size ${params.cut_window_size} \
      --cut_mean_quality ${params.cut_mean_quality} \
      ${adapter_opt} \
      --thread ${task.cpus} \
      --html ${sample_id}.fastp.html \
      --json ${sample_id}.fastp.json
    """
}

workflow {

    if (params.input_dir == null) {
        error "Please provide --input_dir"
    }

    reads_ch = Channel.fromFilePairs(
        "${params.input_dir}/${params.pattern}",
        flat: true
    )

    FASTP_ITS(reads_ch)
}
