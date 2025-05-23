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


focal.events.to.tsv <- function(focal.events, file.name='') {
  if (isempty(file.name)) {
    file.name <- stdout()
  }
  
  fd <- file(file.name, "wb")
  lines <- vapply(focal.events, function(event) {
    percentile_p <- if(is.null(event$perc)) NA else event$perc
    paste(
      event$chromosome, event$loc.start, event$loc.end,
      formatC(percentile_p, format = "e", digits = 5),
      formatC(event$l$p, format="e", digits=5),
      formatC(event$r$p, format="e", digits=5),
      formatC(event$l$q, format="e", digits=5),
      formatC(event$r$q, format="e", digits=5),
      paste0(event$gene.symbols, collapse=","),
      paste0(event$ensembl.id, collapse=","),
      sep='\t'
    )
  }, character(1))
  lines <- c(paste('Chromosome', 'Start', 'End', 'Percentile_pValue',
                   'Left_break_-log10pValue', 'Right_break_-log10pValue',
                   'Left_break_-log10qValue', 'Right_break_-log10qValue',
                   'Gene_symb', 'Ensembl_id', sep='\t'),
             lines)
  writeLines(lines, con=fd, sep='\n')
  flush(fd)
  close(fd)
}