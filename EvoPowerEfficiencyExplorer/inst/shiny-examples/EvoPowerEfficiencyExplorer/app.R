library(shiny)
library(ggplot2)
library(dplyr)

# Core clade data adapted from EvoPowerEfficiency.R
clade_data <- data.frame(
  rank = 1:19,
  taxa = c(
    "Unicells", "Protozoa", "Porifera", "Anthozoa", "Scyphozoa",
    "Nematoda", "Mollusca", "Branchiopoda", "Oligochaeta",
    "Gymnolaemata", "Malacostraca", "Copepoda", "Arachnida",
    "Insecta", "Osteichthyes", "Amphibia", "Squamata",
    "Mammalia", "Aves"
  ),
  b = c(
    0.79, 0.68, 0.55, 0.86, 0.85,
    0.72, 0.75, 0.70, 0.75,
    0.80, 0.78, 0.72, 0.76,
    0.69, 0.76, 0.77, 0.76,
    0.75, 0.68
  ),
  B0 = c(
    0.0365, 0.0088, 0.0247, 0.0738, 0.0135,
    0.0236, 0.1590, 0.0570, 0.0908,
    0.3080, 0.3080, 0.2115, 0.0859,
    0.3655, 0.2870, 0.2960, 0.3800,
    3.5900, 3.8000
  ),
  Mmin = c(
    1e-16, 1e-12, NA, 8e-11, NA,
    7.06e-11, 9.1e-9, NA, 2e-8,
    1e-5, 7.4e-7, 1.1e-8, 1e-5,
    7.4e-9, 2e-5, 5e-4, 5e-4,
    0.002, 0.002
  ),
  Mmax = c(
    4.7e-10, 8e-8, NA, 1e-5, NA,
    1.45e-7, 250, NA, 1.26e-5,
    0.1, 2.8e-4, 9.9e-6, 0.1,
    0.1, 2000, 25, 135,
    181400, 156
  )
)

clade_data <- clade_data %>%
  mutate(
    Bmax = B0 * (Mmax ^ b),
    Bmin = B0 * (Mmin ^ b),
    BM_max = Bmax / Mmax,
    BM_min = Bmin / Mmin
  )

# Defaults inferred from current clade ranges
default_BM_upper <- max(clade_data$BM_min, na.rm = TRUE)
default_BM_lower <- min(clade_data$BM_max, na.rm = TRUE)

code_file <- if (file.exists("EvoPowerEfficiency.R")) {
  "EvoPowerEfficiency.R"
} else {
  system.file("extdata", "EvoPowerEfficiency.R", package = "EvoPowerEfficiencyExplorer")
}
code_lines <- if (nzchar(code_file) && file.exists(code_file)) readLines(code_file, warn = FALSE) else character(0)
code_headings_idx <- grep("^#{1,6}\\s*", code_lines)
code_headings <- if (length(code_headings_idx) > 0) {
  paste0(sprintf("%04d", code_headings_idx), " | ", trimws(code_lines[code_headings_idx]))
} else {
  "No section headings detected"
}

safe_efficiency <- function(M, B0, Bc_over_mc) {
  e <- 1 - (B0 / Bc_over_mc) * M^(-0.25)
  pmin(1, pmax(0, e))
}

mass_grid <- function(log10_min, log10_max, n = 300) {
  10^seq(log10_min, log10_max, length.out = n)
}

ui <- navbarPage(
  title = "Evo Power Efficiency Explorer",

  tabPanel(
    "Overview",
    fluidPage(
      h2("Interactive Explorer for EvoPowerEfficiency.R"),
      p("This Shiny app turns the script into an interactive analysis environment."),
      tags$ul(
        tags$li("Explore how metabolic rate, mass-specific metabolism, and systemic efficiency shift with body mass."),
        tags$li("Compare clades and visualize lineage-level differences in normalization constants (B0)."),
        tags$li("Test bounded scaling predictions for minimum and maximum body size."),
        tags$li("Inspect sections of the original code and connect them to implications.")
      ),
      hr(),
      fluidRow(
        column(
          4,
          h4("Core theoretical relations"),
          tags$pre("B(M) = B0 * M^(3/4)\nB(M)/M = B0 * M^(-1/4)\ne(M) = 1 - (B0/(Bc/mc)) * M^(-1/4)\nde/dM = (B0/(4*Bc/mc)) * M^(-5/4)")
        ),
        column(
          4,
          h4("Summary from clade table"),
          verbatimTextOutput("summary_text")
        ),
        column(
          4,
          h4("Novel findings this app emphasizes"),
          tags$ul(
            tags$li("Efficiency gains with size are real but diminishing, with marginal returns dropping as M^(-5/4)."),
            tags$li("Exponent b clusters around 0.75 while B0 shifts strongly among clades."),
            tags$li("Bounded metabolic intensity implies predictive size limits from B0 and energetic bounds.")
          )
        )
      )
    )
  ),

  tabPanel(
    "Theory Explorer",
    sidebarLayout(
      sidebarPanel(
        sliderInput("logM", "log10 body-mass range (kg)", min = -16, max = 6, value = c(-10, 3), step = 0.5),
        sliderInput("B0_theory", "B0", min = 0.001, max = 5, value = 0.3, step = 0.001),
        sliderInput("Bc_mc", "Bc/mc", min = 0.1, max = 20, value = 1, step = 0.1),
        selectInput(
          "metric_theory",
          "Metric",
          choices = c(
            "Whole-organism power B(M)" = "B",
            "Mass-specific power B/M" = "BM",
            "Efficiency e(M)" = "e",
            "Inefficiency 1-e" = "ineff",
            "Marginal gain de/dM" = "dedM"
          ),
          selected = "e"
        )
      ),
      mainPanel(
        plotOutput("theory_plot", height = "420px"),
        tableOutput("theory_table")
      )
    )
  ),

  tabPanel(
    "Clade Explorer",
    sidebarLayout(
      sidebarPanel(
        selectInput("taxa", "Taxa", choices = clade_data$taxa, selected = clade_data$taxa[1:8], multiple = TRUE),
        selectInput(
          "clade_metric",
          "Curve type",
          choices = c(
            "Metabolic power B(M)" = "B",
            "Mass-specific power B(M)/M" = "BM"
          ),
          selected = "B"
        ),
        helpText("Curves are drawn across each clade's observed mass range [Mmin, Mmax].")
      ),
      mainPanel(
        plotOutput("clade_plot", height = "460px"),
        tableOutput("clade_table")
      )
    )
  ),

  tabPanel(
    "Predictions & Findings",
    sidebarLayout(
      sidebarPanel(
        numericInput("BM_upper", "(B/M)_max (upper bound)", value = signif(default_BM_upper, 4), min = 1e-6, step = 0.01),
        numericInput("BM_lower", "(B/M)_min (lower bound)", value = signif(default_BM_lower, 4), min = 1e-8, step = 0.001),
        checkboxInput("lock_ratio", "Force BM_upper > BM_lower", value = TRUE),
        helpText("Predictions use: Mmin_pred = (B0/(B/M)_max)^4, Mmax_pred = (B0/(B/M)_min)^4")
      ),
      mainPanel(
        fluidRow(
          column(6, plotOutput("pred_min_plot", height = "300px")),
          column(6, plotOutput("pred_max_plot", height = "300px"))
        ),
        fluidRow(
          column(6, plotOutput("scaling_plot", height = "300px")),
          column(6, verbatimTextOutput("findings_text"))
        )
      )
    )
  ),

  tabPanel(
    "Code Navigator",
    fluidPage(
      fluidRow(
        column(
          5,
          selectInput("code_heading", "Jump to section", choices = code_headings, selected = code_headings[1]),
          sliderInput("context_lines", "Context lines", min = 10, max = 120, value = 35, step = 5),
          verbatimTextOutput("section_implication")
        ),
        column(
          7,
          h4("Code snippet"),
          verbatimTextOutput("code_snippet")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  output$summary_text <- renderText({
    mean_b <- mean(clade_data$b, na.rm = TRUE)
    sd_b <- sd(clade_data$b, na.rm = TRUE)
    paste0(
      "Number of clades: ", nrow(clade_data), "\n",
      "Mean scaling exponent b: ", sprintf("%.3f", mean_b), "\n",
      "SD of b: ", sprintf("%.3f", sd_b), "\n",
      "B0 range: ", sprintf("%.4f", min(clade_data$B0)), " to ", sprintf("%.2f", max(clade_data$B0)), "\n",
      "Observed Mmin range: ", format(min(clade_data$Mmin, na.rm = TRUE), scientific = TRUE), " to ", format(max(clade_data$Mmin, na.rm = TRUE), scientific = TRUE), "\n",
      "Observed Mmax range: ", format(min(clade_data$Mmax, na.rm = TRUE), scientific = TRUE), " to ", format(max(clade_data$Mmax, na.rm = TRUE), scientific = TRUE)
    )
  })

  theory_df <- reactive({
    M <- mass_grid(input$logM[1], input$logM[2])
    B <- input$B0_theory * M^(0.75)
    BM <- B / M
    e <- safe_efficiency(M, input$B0_theory, input$Bc_mc)
    ineff <- pmax(0, 1 - e)
    dedM <- (input$B0_theory / (4 * input$Bc_mc)) * M^(-1.25)

    data.frame(M = M, B = B, BM = BM, e = e, ineff = ineff, dedM = dedM)
  })

  output$theory_plot <- renderPlot({
    df <- theory_df()

    if (input$metric_theory %in% c("e", "ineff")) {
      ggplot(df, aes(x = M, y = .data[[input$metric_theory]])) +
        geom_line(linewidth = 1.1, color = "#1F4E79") +
        scale_x_log10() +
        labs(
          x = "Body mass M (kg)",
          y = ifelse(input$metric_theory == "e", "Efficiency e(M)", "Inefficiency 1-e"),
          title = "Efficiency profile"
        ) +
        theme_bw(base_size = 13)
    } else {
      y_label <- switch(
        input$metric_theory,
        B = "B(M)",
        BM = "B(M)/M",
        dedM = "de/dM"
      )

      ggplot(df, aes(x = M, y = .data[[input$metric_theory]])) +
        geom_line(linewidth = 1.1, color = "#1F4E79") +
        scale_x_log10() +
        scale_y_log10() +
        labs(
          x = "Body mass M (kg)",
          y = y_label,
          title = "Scaling relation"
        ) +
        theme_bw(base_size = 13)
    }
  })

  output$theory_table <- renderTable({
    df <- theory_df()
    idx <- unique(round(seq(1, nrow(df), length.out = 6)))
    out <- df[idx, c("M", "B", "BM", "e", "dedM")]
    names(out) <- c("M (kg)", "B(M)", "B/M", "e(M)", "de/dM")
    signif(out, 4)
  })

  clade_curves <- reactive({
    req(length(input$taxa) > 0)

    selected <- clade_data %>% filter(taxa %in% input$taxa)

    pieces <- lapply(seq_len(nrow(selected)), function(i) {
      row <- selected[i, ]
      if (is.na(row$Mmin) || is.na(row$Mmax) || row$Mmax <= row$Mmin) return(NULL)

      M <- exp(seq(log(row$Mmin), log(row$Mmax), length.out = 200))
      B <- row$B0 * M^(row$b)
      BM <- B / M

      data.frame(taxa = row$taxa, M = M, B = B, BM = BM, b = row$b, B0 = row$B0)
    })

    bind_rows(pieces)
  })

  output$clade_plot <- renderPlot({
    df <- clade_curves()
    req(nrow(df) > 0)

    ggplot(df, aes(x = M, y = .data[[input$clade_metric]], color = taxa)) +
      geom_line(linewidth = 1.05) +
      scale_x_log10() +
      scale_y_log10() +
      labs(
        x = "Body mass M (kg)",
        y = ifelse(input$clade_metric == "B", "Metabolic power B(M)", "Mass-specific power B/M"),
        title = "Clade-level scaling envelopes",
        color = "Taxa"
      ) +
      theme_bw(base_size = 13)
  })

  output$clade_table <- renderTable({
    selected <- clade_data %>%
      filter(taxa %in% input$taxa) %>%
      select(taxa, b, B0, Mmin, Mmax)
    signif(selected, 4)
  })

  pred_data <- reactive({
    BM_upper <- input$BM_upper
    BM_lower <- input$BM_lower

    if (isTRUE(input$lock_ratio) && BM_upper <= BM_lower) {
      BM_upper <- BM_lower * 1.01
    }

    clade_data %>%
      mutate(
        Mmin_pred = (B0 / BM_upper)^4,
        Mmax_pred = (B0 / BM_lower)^4,
        size_ratio = Mmax / Mmin
      )
  })

  output$pred_min_plot <- renderPlot({
    df <- pred_data() %>% filter(!is.na(Mmin), !is.na(Mmin_pred))
    req(nrow(df) > 2)

    fit <- lm(log10(Mmin) ~ log10(Mmin_pred), data = df)

    ggplot(df, aes(x = Mmin_pred, y = Mmin)) +
      geom_point(size = 2.6, color = "#0B6E4F") +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#B22222") +
      geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 1) +
      scale_x_log10() +
      scale_y_log10() +
      labs(
        title = "Prediction test: minimum size",
        x = "Predicted Mmin",
        y = "Observed Mmin"
      ) +
      theme_bw(base_size = 12)
  })

  output$pred_max_plot <- renderPlot({
    df <- pred_data() %>% filter(!is.na(Mmax), !is.na(Mmax_pred))
    req(nrow(df) > 2)

    fit <- lm(log10(Mmax) ~ log10(Mmax_pred), data = df)

    ggplot(df, aes(x = Mmax_pred, y = Mmax)) +
      geom_point(size = 2.6, color = "#6A1B9A") +
      geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "#B22222") +
      geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 1) +
      scale_x_log10() +
      scale_y_log10() +
      labs(
        title = "Prediction test: maximum size",
        x = "Predicted Mmax",
        y = "Observed Mmax"
      ) +
      theme_bw(base_size = 12)
  })

  output$scaling_plot <- renderPlot({
    df <- pred_data() %>% filter(!is.na(Mmin), !is.na(B0))
    req(nrow(df) > 2)

    ggplot(df, aes(x = B0, y = Mmin)) +
      geom_point(size = 2.6, color = "#7A3E00") +
      geom_smooth(method = "lm", se = FALSE, color = "black", linewidth = 1) +
      scale_x_log10() +
      scale_y_log10() +
      labs(
        title = "Scaling implication: Mmin vs B0",
        x = "B0",
        y = "Mmin"
      ) +
      theme_bw(base_size = 12)
  })

  output$findings_text <- renderText({
    df <- pred_data()

    df_min <- df %>% filter(!is.na(Mmin), !is.na(Mmin_pred))
    df_max <- df %>% filter(!is.na(Mmax), !is.na(Mmax_pred))

    fit_min <- lm(log10(Mmin) ~ log10(Mmin_pred), data = df_min)
    fit_max <- lm(log10(Mmax) ~ log10(Mmax_pred), data = df_max)
    fit_b <- lm(b ~ 1, data = df)

    slope_min <- coef(fit_min)[2]
    slope_max <- coef(fit_max)[2]
    mean_b <- coef(fit_b)[1]
    sd_b <- sd(df$b, na.rm = TRUE)

    paste0(
      "Novel-finding diagnostics\n\n",
      "1) Exponent stability\n",
      "   mean(b) = ", sprintf("%.3f", mean_b), ", sd(b) = ", sprintf("%.3f", sd_b), "\n",
      "   Interpretation: b is comparatively stable across clades relative to B0 variation.\n\n",
      "2) Predictive bound test\n",
      "   slope observed~predicted (Mmin) = ", sprintf("%.3f", slope_min), "\n",
      "   slope observed~predicted (Mmax) = ", sprintf("%.3f", slope_max), "\n",
      "   Interpretation: slopes closer to 1 indicate stronger support for bound-based predictions.\n\n",
      "3) Diminishing returns implication\n",
      "   de/dM scales as M^(-5/4), so gains from increasing size fall rapidly with body mass."
    )
  })

  output$code_snippet <- renderText({
    if (length(code_lines) == 0) {
      return("EvoPowerEfficiency.R not found in this directory.")
    }

    idx <- as.integer(substr(input$code_heading, 1, 4))
    n <- input$context_lines
    from <- max(1, idx - n)
    to <- min(length(code_lines), idx + n)

    snippet <- paste0(sprintf("%04d", from:to), ": ", code_lines[from:to], collapse = "\n")
    snippet
  })

  output$section_implication <- renderText({
    label <- input$code_heading

    if (grepl("Prediction 1", label, fixed = TRUE)) {
      return("Implication: whole-organism power rises sublinearly with size, enabling economies of scale.")
    }
    if (grepl("Prediction 2", label, fixed = TRUE)) {
      return("Implication: mass-specific metabolism declines with size, supporting efficiency gains in larger organisms.")
    }
    if (grepl("Prediction 3", label, fixed = TRUE)) {
      return("Implication: efficiency saturates and marginal improvements diminish, constraining evolutionary payoffs of size increase.")
    }
    if (grepl("Prediction 4", label, fixed = TRUE)) {
      return("Implication: clades can diverge strongly in B0 while preserving similar scaling exponents.")
    }
    if (grepl("envelope", tolower(label), fixed = TRUE)) {
      return("Implication: bounded mass-specific metabolic intensity defines a trait-space envelope that predicts feasible size limits.")
    }

    "Implication: this section contributes to testing or extending bounded scaling predictions across taxa."
  })
}

shinyApp(ui = ui, server = server)
