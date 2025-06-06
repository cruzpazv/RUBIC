# Copyright 2015 Netherlands Cancer Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

seg.cna.columns <- c("Sample", "Chromosome", "Start", "End", "LogRatio")
markers.columns <- c("Name", "Chromosome", "Position")
genes.columns <- c("ID", "Name", "Chromosome", "Start", "End")

# The following is necessary to silence warning for CMD CHECK on variable defined
# in inner scopes of data.table and ggplot2
globalVariables(c(seg.cna.columns, markers.columns, genes.columns,
                'i.LogRatio', 'Segment', 'SegmentGrp', 'ProbesNo', 'Probe', 'CNV',
                'AbsPosition', 'N', 'Position2', 'Mu',
                '.I', '.N', '.', ':=', '.GRP', '.SD', 'J',
                'ChromosomeStart'))

#' @title RUBIC Class
#' @description A ReferenceClass that contains all the data needed and generated by the RUBIC algorithm.
#' 
#' @field fdr Event based false discovery rate.
#' @field genes A data.table containg the gene locations.
#' @field samples A character vector containing sample IDs.
#' @field markers A data.table containing the markers information.
#' @field map.loc A data table containing the markers mapped on the segments.
#' @field min.mean The minimum mean copy number allowed.
#' @field max.mean The maximum mean copy number allowed.
#' @field min.probes The minimum number of probes to be considered in the analysis.
#' @field min.seg.markers The number of probes allowed in each segment.
#' @field amp.level The threshold used for calling amplifications.
#' @field del.level The threshold used for calling deletions.
#' @field focal.threshold The maximum length of a recurrent region to be called focal.
#'
#' @details It is possible and recommended to instanciate a new RUBIC object by using the
#'          convenience function \code{\link{rubic}}.
#'
#' @seealso \code{\link{rubic}}
#' @importFrom methods setRefClass
#' @importFrom data.table data.table
RUBIC <- setRefClass('RUBIC',
         fields=list(
           fdr="numeric",
           genes="data.table",
           samples="vector",
           markers="data.table",
           map.loc="data.table",
           min.mean="numeric",
           max.mean="numeric",
           min.probes="numeric",
           min.seg.markers="numeric",
           amp.level="numeric",
           del.level="numeric",
           focal.threshold="numeric",
           # The following are for nternal use only
           params.p="list",
           params.n="list",
           cna.matrix="matrix",
           map.loc.agr="data.table",
           segments.p="list",
           segments.n="list",
           e.p="numeric",
           e.n="numeric",
           called.p.events="list",
           called.n.events="list",
           focal.p.events="list",
           focal.n.events="list",
           q.all='numeric'
           
         ),
         methods=list(
           initialize = function(fdr=NULL, seg.cna=NULL, markers=NULL,
                                 samples=NULL, genes=NULL,
                                 amp.level=0.1, del.level=-0.1,
                                 min.seg.markers=1,
                                 min.mean=NA_real_, max.mean=NA_real_,
                                 min.probes=2.6e5, focal.threshold=10e6,
                                 seg.cna.header=T, markers.header=T, samples.header=F,
                                 col.sample=1, col.chromosome=2, col.start=3,
                                 col.end=4, col.log.ratio=6,
                                 ...) {
             
             "Create a new RUBIC object. It is recommended to use the \\link{rubic} function instead
             of calling this method directly.
             See \\link{rubic} for parameter descriptions."
             
             errors <- vector('character')
            
             if (amp.level <= 0)
               errors <- c(errors, "The threshold for calling amplifications must be > 0")
             if (del.level >= 0)
               errors <- c(errors, "The threshold for calling deletions must be < 0")
             if (min.seg.markers <= 0)
               errors <- c(errors, "The minimum number of probes allowed in each segment must be > 0")
             if (focal.threshold < 1)
               errors <- c(errors, "The focal threshold must be > 0")
             if (min.probes < 1)
               errors <- c(errors, "The minimum number of probes considered for the analysis must be > 0")
             if (!is.null(fdr) && (fdr > 1 || fdr < 0))
                 errors <- c(errors, "The FDR must be a real value between 0 and 1")
             
             if (length(errors) > 0)
               stop(paste(errors, collapse='\n'))
             
             amp.level <<- amp.level
             del.level <<- del.level
             min.seg.markers <<- min.seg.markers
             max.mean <<- max.mean
             min.mean <<- min.mean
             focal.threshold <<- focal.threshold
             min.probes <<- min.probes
             fdr <<- as.numeric(fdr)
             
             if (!is.null(seg.cna)) {
               # If seg.cna is a string then read the file
               if (is.character(seg.cna)) {
                 seg.cna <- read.seg.file(seg.cna, header=seg.cna.header,
                                          sample=col.sample,
                                          chromosome=col.chromosome,
                                          start=col.start,
                                          end=col.end,
                                          log.ratio=col.log.ratio)
               } else {
                 if (!is.data.table(seg.cna)) {
                   # Otherwise if it is not a data.table try to convert it into one
                   seg.cna <- as.data.table(seg.cna)
                 }
                 
                 # Remove unwanted columns by reference
                 remove.columns <- which(!(colnames(seg.cna) %in% seg.cna.columns))
                 if (length(remove.columns) > 0) {
                  seg.cna[,eval(remove.columns):=NULL]
                 }
                 
                 # Make sure chromosomes stay ordered independently of their alphabetical order
                 chromosome.levels <- extract.chromosome.levels(seg.cna)
                 seg.cna[,Chromosome:=ordered(toupper(Chromosome), chromosome.levels)]
                 
                 # Check if the data.table contains all the necessary columns
                 if (!all(seg.cna.columns %in% colnames(seg.cna))) {
                   stop(paste('Invalid seg.cna. It must contain a least the following columns:',
                              paste(seg.cna.columns, collapse=', ')))
                 }
               }
               
               if (NROW(seg.cna) == 0) {
                 stop('Empty seg.cna')
               }
             }
             
             if (!is.null(markers)) {
               if (is.character(markers)) {
                 markers <<- read.markers(markers, header=markers.header)
               } else {
                 if (!is.data.table(markers)) {
                   # Otherwise if it is not a data.table try to convert it into one
                   markers <<- as.data.table(markers)
                 } else {
                   markers <<- markers
                 }
                 
                 # Remove unwanted columns by reference
                 remove.columns <- which(!(colnames(.self$markers) %in% markers.columns))
                 if (length(remove.columns) > 0) {
                  .self$markers[,eval(remove.columns):=NULL]
                 }
                 
                 # Make sure chromosomes stay ordered independently of their alphabetical order
                 chromosome.levels <- extract.chromosome.levels(.self$markers)
                 markers <<- unique(.self$markers[,Chromosome:=ordered(toupper(Chromosome), chromosome.levels)], by=c('Chromosome', 'Position'))
                 
                 # Check if the data.table contains all the necessary columns
                 if (!all(markers.columns %in% colnames(.self$markers))) {
                   stop(paste('Invalid markers. It must contain a least the following columns:',
                              paste(markers.columns, collapse=', ')))
                 }
               }
               
               if (NROW(.self$markers) == 0) {
                 stop('Empty markers')
               }
             }
            
             if (length(samples) == 1) {
               if (file.access(samples, mode=4) == -1)
                 stop(paste('The samples file', samples, 'cannot be found or read'))
               samples.dt <- fread(samples, header=samples.header)
               if (NCOL(samples.dt) > 2)
                 warning('The samples file contains more than one columns. Using first')
               if (NROW(samples.dt) == 0)
                 warning('The samples file dont contain any sample. Using all available samples')
               if (NROW(samples.dt) == 1)
                 stop('The samples file contains only one sample. Minimum is two')
               samples <<- as.character(samples.dt[[1]])
             } else {
               samples <<- as.character(samples)
             }
             
             if (!is.null(seg.cna) && !is.null(markers)) {
               map.loc <<- preprocess.map.loc(seg.cna, .self$markers, .self$samples,
                                              min.seg.markers=min.seg.markers,
                                              min.mean=min.mean, max.mean=max.mean)
               
               map.loc <<- ensure.min.probes(map.loc, .self$markers,
                                             min.probes=min.probes)
             }
             
             if (!is.null(genes)) {
               if (is.character(genes)) {
                 genes <<- read.genes.info.tsv(genes)
               } else {
                 if (!is.data.table(genes)) {
                   # Otherwise if it is not a data.table try to convert it into one
                   genes <<- as.data.table(genes)
                 }
                 genes <<- genes
               }
               # Check if the data.table contains all the necessary columns
               if (!all(genes.columns %in% colnames(.self$genes))) {
                 stop(paste('Invalid gene locations. It must contain a least the following columns:',
                            paste(genes.columns, collapse=', ')))
               }
               
               if (NROW(.self$genes) == 0) {
                 stop('Empty gene locations')
               }
             } else {
               genes <<- data.table()
             }
             
             params.p <<- list()
             params.n <<- list()
             cna.matrix <<- matrix(ncol=0,nrow=0)
             map.loc.agr <<- data.table()
             segments.p <<- list()
             segments.n <<- list()
             e.p <<- NA_real_
             e.n <<- NA_real_
             called.p.events <<- list()
             called.n.events <<- list()
             focal.p.events <<- list()
             focal.n.events <<- list()
             q.all <<- vector('numeric')
             
             callSuper(...)
           },
           
           estimate.parameters = function(quiet=T, test.env=NULL) {
             "Estimate the parameters necessary for segmentation and event calling."
             
             if (length(params.p) > 0 || length(params.n) > 0) {
               warning('Parameters have been already estimated. Recomputing...')
             }
             
             cna.matrix <<- extract.matrix(map.loc)
             map.loc.agr <<- sum.map.loc(map.loc)
             max.chrom.len <- max.chrom.length(map.loc)
             
             params <- RUBIC:::estimate.parameters(cna.matrix, map.loc.agr,
                                                   max.chrom.len,
                                                   amp.level, del.level, fdr,
                                                   quiet=quiet, test.env=test.env)
             params.p <<- params$params.p
             params.n <<- params$params.n
           },
           
           segment = function() {
             "Generate positive and negative segments."
             
             if (length(segments.p) > 0 || length(segments.n) > 0) {
               warning('Data have been already segmented. Recomputing...')
             }
             if (length(params.p) == 0 || length(params.n) == 0) {
               estimate.parameters()
             }
             
             if (isempty(cna.matrix)) cna.matrix <<- extract.matrix(map.loc)
             if (isempty(map.loc.agr)) map.loc.agr <<- sum.map.loc(map.loc)
             
             segments <- aggregate.segments(cna.matrix, map.loc.agr,
                                            amp.level, del.level,
                                            params.p, params.n, fdr)
             segments.p <<- segments$segments.p
             e.p <<- segments$e.p
             segments.n <<- segments$segments.n
             e.n <<- segments$e.n
           },
           
           call.events = function() {
             "Call recurrent events."
             
             if (length(called.p.events) > 0 || length(called.n.events) > 0) {
               warning('Events have been already called. Recomputing...')
             }
             if (length(segments.p) == 0 || length(segments.n) == 0) {
               segment()
             }
             
             if (isempty(cna.matrix)) cna.matrix <<- extract.matrix(map.loc)
             
             called.p.events <<- RUBIC:::call.events(cna.matrix,
                                                     amp.level, del.level,
                                                     segments.p, params.p,
                                                     fdr, e.p, +1)
             called.n.events <<- RUBIC:::call.events(cna.matrix,
                                                     amp.level, del.level,
                                                     segments.n, params.n,
                                                     fdr, e.n, -1)
           },
           
           call.focal.events = function(genes=NULL) {
             "Call focal events."
             
             if (length(focal.p.events) > 0 || length(focal.n.events) > 0) {
               warning('Focal events have been already called. Recomputing...')
             }
             if (length(called.p.events) == 0 || length(called.n.events) == 0) {
               call.events()
             }
             
             if (!is.null(genes)) {
               if (is.character(genes)) {
                 genes <<- read.genes.info.tsv(genes)
               } else {
                 if (!is.data.table(genes)) {
                   # Otherwise if it is not a data.table try to convert it into one
                   genes <<- as.data.table(genes)
                 }
                 genes <<- genes
               }
               # Check if the data.table contains all the necessary columns
               if (!all(genes.columns %in% colnames(.self$genes))) {
                 stop(paste('Invalid gene locations. It must contain a least the following columns:',
                            paste(genes.columns, collapse=', ')))
               }
               
               if (NROW(.self$genes) == 0) {
                 stop('Empty gene locations')
               }
             }
             
             if (isempty(map.loc.agr)) map.loc.agr <<- sum.map.loc(map.loc)
             
             if (NROW(.self$genes) == 0) {
               genes <<- read.genes.info.biomart(filter.chr=levels(map.loc.agr[,Chromosome]))
             }
             
             focal.p.events <<- called.to.genes(map.loc.agr, called.p.events,
                                                focal.threshold,
                                                .self$genes, markers)
             focal.n.events <<- called.to.genes(map.loc.agr, called.n.events,
                                                focal.threshold,
                                                .self$genes, markers)
             focals <- calc.break.qvalues(focal.p.events, focal.n.events)
             focal.p.events <<- sort.regions.on.genome(focals$focal.p.events)
             focal.n.events <<- sort.regions.on.genome(focals$focal.n.events)
             q.all <<- focals$q.all
           },
           
           save = function(file) {
             "Save the current state of the RUBIC object to file."
             
             # Remove unnecessary data that will be recomputed at the next run
             cna.matrix <<- matrix(ncol=0, nrow=0)
             map.loc.agr <<- data.table()
             
             saveRDS(.self, file=file)
           },
           
           save.focal.gains = function(file) {
             "Save focal gains to a file in TSV format."
             
             if (length(q.all) == 0) {
               call.focal.events()
             }
             focal.events.to.tsv(focal.p.events, file)
           },
           
           save.focal.losses = function(file) {
             "Save focal losses to a file in TSV format."
             
             if (length(q.all) == 0) {
               call.focal.events()
             }
             focal.events.to.tsv(focal.n.events, file)
           },
           
           save.plots = function(dir, genes=NULL, steps=T, width=11, height=5, extension="png") {
             "Save gains and losses plots for each chromosome."
             
             if (length(q.all) == 0) {
               call.focal.events()
             }
             
             custom.genes <- NULL
             if (!is.null(genes)) {
               if (is.character(genes)) {
                 custom.genes <- read.genes.info.tsv(genes)
               } else {
                 if (!is.data.table(genes)) {
                   # Otherwise if it is not a data.table try to convert it into one
                   custom.genes <- as.data.table(genes)
                 } else {
                   custom.genes <- genes
                 }
               }
               # Check if the data.table contains all the necessary columns
               if (!all(genes.columns %in% colnames(custom.genes))) {
                 stop(paste('Invalid gene locations. It must contain a least the following columns:',
                            paste(genes.columns, collapse=', ')))
               }
               
               if (NROW(custom.genes) == 0) {
                 stop('Empty gene locations')
               }
             }
             
             if (NROW(custom.genes) == 0) {
               generate.all.plots(dir=dir, map.loc=map.loc, amp.level=amp.level, del.level=del.level,
                                  segments.p=segments.p, segments.n=segments.n,
                                  focal.p.events=focal.p.events, focal.n.events=focal.n.events,
                                  markers=markers, steps=steps, genes=genes,
                                  width=width, height=height, extension=extension)
             } else {
               generate.all.plots(dir=dir, map.loc=map.loc, amp.level=amp.level, del.level=del.level,
                                  segments.p=segments.p, segments.n=segments.n,
                                  focal.p.events=focal.p.events, focal.n.events=focal.n.events,
                                  markers=markers, steps=steps, genes=custom.genes,
                                  width=width, height=height, extension=extension)
             }
           }
           
         )
)

#' @title Create a new RUBIC object
#' 
#' @description With this function it is possible to create and initialize a new RUBIC object.
#' 
#' @param fdr A number indicating the wanted event based false discovery rate. For example 0.25.
#' @param seg.cna Either a character string naming a file or a \code{\link[data.table]{data.table}} containing the segmented CNA data in appropriate format.
#'                In case a file name is provided the file will be open and read as a \code{\link[data.table]{data.table}}.
#' @param markers Either a character string naming a file or a \code{\link[data.table]{data.table}} containing the markers information in appropriate format.
#'                In case a file name is provided the file will be opened and read as a \code{\link[data.table]{data.table}}.
#' @param samples Either a character string naming a file or a character vector containing the sample IDs used for the analysis.
#'                In case a file name is provided the file will be open and read as a \code{\link[data.table]{data.table}}.
#'                In case this parameter is not specified, all the samples presents in the \code{seg.cna} file will be used.
#' @param genes Either a character string naming a file or a \code{\link[data.table]{data.table}} containing the gene locations in appropriate format.
#'              In case a file name is provided the file will be open and read as a \code{\link[data.table]{data.table}}.
#'              In case this parameter is not specified, RUBIC will attempt to download the most recent annotations using \href{http://www.biomart.org}{Biomart}.
#' @param amp.level A positive number specifying the threshold used for calling amplifications. The default value is set to 0.1.
#' @param del.level A negative number specifying the threshold used for calling deletions. The default value is set to -0.1.
#' @param min.seg.markers A positive integer specifying the number of probes allowed in each segment. The default value is set to 1, which means that no segments will be merged.
#'                        If this parameter is set to a number larger than 1, all segments with less than \code{min.seg.markers} will be joined with
#'                        adjacent segments until a segment with at least \code{min.seg.markers} will be formed.
#' @param min.mean A number specifying the minimum mean copy number allowed. By default segments will not be filtered based on their minimum mean copy number.
#' @param max.mean A number specifying the maximum mean copy number allowed. By default segments will not be filtered based on their maximum mean copy number.
#' @param min.probes The minimum number of probes to be considered in the analysis.
#' @param focal.threshold The maximum length of a recurrent region to be called focal. Only regions smaller than \code{focal.threshold} bases will be called focal.
#'                        By default 10000000 bases.
#' @param seg.cna.header A logical value indicating whether the seg.cna file contains the names of the variables as its first line.
#'                       The default is set to \code{TRUE}.
#' @param markers.header A logical value indicating whether the markers file contains the names of the variables as its first line.
#'                       The default is set to \code{TRUE}.
#' @param samples.header A logical value indicating whether the samples file contains the names of the variables as its first line.
#'        Please notice that while the default value of \code{seg.cna.header} and \code{markers.header} is set to \code{TRUE},
#'        RUBIC \emph{do not} expect a header by default for the samples file (and, therefore, this value is set
#'        by default to \code{FALSE}).
#' @param col.sample The number of the column containing the sample name in the \code{seg.cna} file.
#'        By default, RUBIC expects the sample name to be in the 1st column.
#' @param col.chromosome The number of the column containing the chromosome name in the \code{seg.cna} file.
#'        By default, RUBIC expects the chromosome name to be in the 2nd column.
#' @param col.start The number of the column containing the start position of each segment in the \code{seg.cna} file.
#'        By default, RUBIC expects the start position to be in the 3rd column.
#' @param col.end The number of the column containing the end position of each segment in the \code{seg.cna} file.
#'        By default, RUBIC expects the end position to be in the 4th column.
#' @param col.log.ratio The number of the column containing the log.ratio name in the \code{seg.cna} file.
#'        By default, RUBIC expects the log.ratio to be in the 6th column.
#' @param ... Additional arguments to be passed to the constructor. Reserved for future use.
#' 
#' @details In order to use the RUBIC method it is necessary to create e initialize a new RUBIC object
#'          using data and parameters specific to your analysis. This function reads and preprocesses all
#'          the data and returns an object of the \code{\link[=RUBIC-class]{RUBIC}} class. It is possible to start the analysis
#'          using the method \code{estimate.parameters} or any other method of the \code{\link[=RUBIC-class]{RUBIC}} class.
#' 
#' @return A new RUBIC object.
#' @seealso \code{\link{RUBIC-class}}
#' @export
rubic <- function(fdr, seg.cna, markers,
                  samples=NULL, genes=NULL,
                  amp.level=0.1, del.level=-0.1,
                  min.seg.markers=1,
                  min.mean=NA_real_, max.mean=NA_real_,
                  min.probes=2.6e5, focal.threshold=10e6,
                  seg.cna.header=T, markers.header=T, samples.header=F,
                  col.sample=1, col.chromosome=2, col.start=3,
                  col.end=4, col.log.ratio=6,
                  ...) {
  
  error <- character(0)
  if (missing(fdr)) {
    error <- c(error, 'fdr')
  }
  if (missing(seg.cna)) {
    error <- c(error, 'seg.cna')
  }
  if (missing(markers)) {
    error <- c(error, 'markers')
  }
  if (length(error) > 0) {
    stop(paste('The', paste(error, collapse=', '), 'parameter must be specified.'))
  }
  rubic.constructor <- match.call()
  rubic.constructor[[1]] <- RUBIC$new
  eval(rubic.constructor, parent.frame())
}

