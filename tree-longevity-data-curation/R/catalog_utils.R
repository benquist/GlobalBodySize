# catalog_utils.R
# Helpers for rendering status badges and summary tables in catalog.Rmd.

#' Return a colored HTML badge for download status.
status_badge <- function(status) {
  switch(status,
    "YES"     = '<span style="background:#28a745;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#10003; Automated</span>',
    "PARTIAL" = '<span style="background:#fd7e14;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#9888; Partial</span>',
    "NO"      = '<span style="background:#dc3545;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#10007; Manual required</span>',
    '<span style="background:#6c757d;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">Unknown</span>'
  )
}

#' Return an HTML badge for QA status.
qa_badge <- function(status) {
  switch(status,
    "PASS"    = '<span style="background:#28a745;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#10003; PASS</span>',
    "WARN"    = '<span style="background:#ffc107;color:#000;padding:2px 8px;border-radius:4px;font-size:0.85em">&#9888; WARN</span>',
    "FAIL"    = '<span style="background:#dc3545;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#10007; FAIL</span>',
    "NOT RUN" = '<span style="background:#6c757d;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">&#9744; Not run</span>',
    '<span style="background:#6c757d;color:#fff;padding:2px 8px;border-radius:4px;font-size:0.85em">Unknown</span>'
  )
}

#' Build a one-row summary data.frame for the overview table.
catalog_row <- function(id, name, folder, downloadable, download_date,
                        n_records, qa_status) {
  data.frame(
    ID            = id,
    Dataset       = name,
    Folder        = folder,
    Downloadable  = downloadable,
    Download_Date = download_date,
    N_Records     = n_records,
    QA            = qa_status,
    stringsAsFactors = FALSE
  )
}
