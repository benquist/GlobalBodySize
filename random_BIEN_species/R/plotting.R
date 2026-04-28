# =============================================================================
# R/plotting.R
# Purpose : Produce the realized climate-niche figure — a 2D density plot of
#           occurrence points in BIO1 (temperature) vs BIO12 (precipitation)
#           climate space.
#
# Ecological context (ecology-user Steps 4 & 11 — Trait-Environment Mapping
#                     and Ecological Plausibility):
#   The 2D climate-space plot is one of the oldest and most intuitive ways to
#   visualize a species' realized climate niche (Whittaker 1975 biome diagram).
#   Plotting occurrence points in BIO1 × BIO12 space shows:
#     - The central tendency of the climate envelope (high-density region)
#     - The tails and outliers (rare climate conditions where the species occurs)
#     - The overall shape of the niche (unimodal peak, elongated, multimodal)
#
#   Interpretation caveats:
#     - This is the REALIZED niche, not the FUNDAMENTAL niche. BIEN records
#       include only locations where the species was observed, not all
#       climatically suitable locations.
#     - Sampling bias (collector effort) distorts density estimates. High
#       density in climate space may reflect intense sampling in one region,
#       not true niche optimum.
#     - BIO1 is reported by WorldClim as °C × 10 (integers). Divide by 10
#       to get °C for axis labeling. This function does NOT rescale BIO1 —
#       the raw WorldClim values are plotted. Keep this in mind when reading
#       the x-axis.
#
#   References:
#   Whittaker, R. H. (1975). Communities and Ecosystems (2nd ed.). Macmillan.
#   Elith, J., and Leathwick, J. R. (2009). Species distribution models.
#     Annual Review of Ecology, Evolution, and Systematics, 40, 677–697.
#     https://doi.org/10.1146/annurev.ecolsys.110308.120159
# =============================================================================


# --------------------------------------------------------------------------- #
# Climate niche plotter
#
# Usage : plot_climate_niche(
#           data       = occ_climate,
#           bio_x      = "BIO1",
#           bio_y      = "BIO12",
#           output_png = "outputs/climate_niche_bio1_bio12.png"
#         )
#
# Input:
#   data       — data.frame from extract_climate_values(); must contain numeric
#                columns named `bio_x` and `bio_y` (e.g., BIO1, BIO12).
#                Rows with NA in either BIO column are silently removed before
#                plotting (NA = ocean or no-data raster cell).
#   bio_x      — name of the x-axis BIO layer (default: "BIO1")
#   bio_y      — name of the y-axis BIO layer (default: "BIO12")
#   output_png — path to write the PNG figure (directory must exist)
#   bins       — number of hexagonal or rectangular bins for 2D density;
#                higher = finer resolution but noisier at edges (default: 45)
#   width/height/dpi — figure dimensions for publication-quality output
#
# Output: the path to the saved PNG (returned invisibly)
#
# Plot anatomy:
#   - stat_bin2d: 2D histogram — occurrence points counted per rectangular bin;
#                 fill colour encodes count (viridis "C" palette, dark = low,
#                 bright = high)
#   - geom_density_2d: kernel density contours overlaid in white — these show
#                      the shape of the distribution independent of bin size
#   - The combination of binned counts + contours allows readers to see both
#     the magnitude (colour) and shape (contours) of the climate envelope
#
# Saving note:
#   ggplot2::ggsave() writes to the specified path. PNG format is used (not PDF)
#   for web and presentation use; for manuscripts, change to ".pdf" and omit dpi.
# --------------------------------------------------------------------------- #
plot_climate_niche <- function(data,
                               bio_x      = "BIO1",
                               bio_y      = "BIO12",
                               output_png = "outputs/climate_niche_bio1_bio12.png",
                               bins       = 45,
                               width      = 8,
                               height     = 6,
                               dpi        = 300) {

  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required. Install with install.packages('ggplot2').")
  }

  if (!(bio_x %in% names(data)) || !(bio_y %in% names(data))) {
    stop("Plot variables not present in data: ", bio_x, ", ", bio_y)
  }

  # Extract the two BIO columns; coerce to numeric and drop NAs
  # (NAs arise from ocean cells or raster no-data regions)
  plot_df <- data.frame(
    x = suppressWarnings(as.numeric(data[[bio_x]])),
    y = suppressWarnings(as.numeric(data[[bio_y]]))
  )
  plot_df <- plot_df[is.finite(plot_df$x) & is.finite(plot_df$y), , drop = FALSE]

  # 2D histogram + kernel density contour overlay
  # aes(x, y): occurrence density in climate space (not geographic space)
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = x, y = y)) +
    # Rectangular 2D bins, fill = count of occurrences per bin
    ggplot2::stat_bin2d(bins = bins) +
    # Kernel density contours (white) help visualise niche shape regardless of bin grid
    ggplot2::geom_density_2d(color = "white", linewidth = 0.3, alpha = 0.6) +
    # Viridis colour scale — perceptually uniform, colour-blind safe, prints well in greyscale
    ggplot2::scale_fill_viridis_c(name = "Count", option = "C") +
    ggplot2::labs(
      title    = "Climate Niche Space",
      subtitle = paste0("Density in ", bio_x, " vs ", bio_y),
      x        = bio_x,
      y        = bio_y
    ) +
    ggplot2::theme_minimal(base_size = 12)

  ggplot2::ggsave(
    filename = output_png,
    plot     = p,
    width    = width,
    height   = height,
    dpi      = dpi
  )

  invisible(output_png)
}
