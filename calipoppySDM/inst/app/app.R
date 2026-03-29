library(shiny)
library(shinydashboard)
library(leaflet)
library(dplyr)
library(terra)
library(raster)
library(maxnet)
library(ggplot2)
library(BIEN)
library(pROC)
library(viridis)
library(geodata)
library(plotly)
library(DT)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SPECIES     <- "Eschscholzia californica"
CA_EXT      <- terra::ext(-125, -114, 32, 42)
ALL_SSPS    <- c("126", "245", "370", "585")
ALL_GCMS    <- get(".cmods", envir = asNamespace("geodata"))
set.seed(2026)
SELECTED_GCMS <- sample(ALL_GCMS, 3)
BIO_LABELS  <- c(
  bio1  = "Mean Annual Temp (°C×10)",   bio2  = "Mean Diurnal Range",
  bio3  = "Isothermality",              bio4  = "Temp Seasonality",
  bio5  = "Max Temp Warmest Month",     bio6  = "Min Temp Coldest Month",
  bio7  = "Temp Annual Range",          bio8  = "Mean Temp Wettest Qtr",
  bio9  = "Mean Temp Driest Qtr",       bio10 = "Mean Temp Warmest Qtr",
  bio11 = "Mean Temp Coldest Qtr",      bio12 = "Annual Precipitation (mm)",
  bio13 = "Precip Wettest Month",       bio14 = "Precip Driest Month",
  bio15 = "Precip Seasonality (CV)",    bio16 = "Precip Wettest Qtr",
  bio17 = "Precip Driest Qtr",          bio18 = "Precip Warmest Qtr",
  bio19 = "Precip Coldest Qtr"
)

harmonize_bioc_names <- function(x) {
  nm <- names(x)
  idx <- suppressWarnings(as.integer(sub("^bio0*([0-9]+)$", "\\1", nm, ignore.case = TRUE)))
  if (any(is.na(idx))) {
    idx <- suppressWarnings(as.integer(sub(".*_([0-9]+)$", "\\1", nm)))
  }
  if (all(!is.na(idx)) && length(idx) == terra::nlyr(x)) {
    names(x) <- paste0("bio", idx)
  }
  x
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- dashboardPage(
  skin = "green",

  dashboardHeader(
    title = tags$span(
      tags$img(src = "https://upload.wikimedia.org/wikipedia/commons/thumb/6/64/California_poppy_2.jpg/240px-California_poppy_2.jpg",
               height = "28px", style = "margin-right:6px; border-radius:3px;"),
      "CA Poppy SDM"
    )
  ),

  dashboardSidebar(
    sidebarMenu(
      menuItem("Distribution Map",   tabName = "map",        icon = icon("map")),
      menuItem("Model Performance",  tabName = "perf",       icon = icon("chart-line")),
      menuItem("Response Curves",    tabName = "response",   icon = icon("chart-area")),
      menuItem("Future Projections", tabName = "future",     icon = icon("cloud-sun-rain")),
      menuItem("Variable Importance",tabName = "importance", icon = icon("list-ol")),
      menuItem("About",              tabName = "about",      icon = icon("info-circle"))
    ),
    hr(),
    tags$div(style = "padding: 0 15px;",
      tags$h5(tags$em(SPECIES), style = "color:#aee8b0; font-style:italic; margin-top:0;"),
      tags$h6("Model Settings", style = "color:#ccc; text-transform:uppercase; letter-spacing:1px;"),
      numericInput("n_bg", "Background points",
                   value = 5000, min = 1000, max = 20000, step = 1000),
      sliderInput("train_frac", "Training fraction",
                  min = 0.5, max = 0.9, value = 0.8, step = 0.05),
      selectInput("classes", "MaxEnt feature classes",
                  choices = c(
                    "Linear + Quadratic"         = "lq",
                    "LQ + Hinge + Product"       = "lqhp",
                    "All (LQ + Hinge + Product + Threshold)" = "lqhpt"
                  ),
                  selected = "lqhp"),
      selectInput("future_time", "Future projection period",
                  choices = c("2021-2040", "2041-2060", "2061-2080", "2081-2100"),
                  selected = "2041-2060"),
      checkboxInput("run_future", "Run future projections (all SSPs x 3 random GCMs)", TRUE),
      helpText(paste("Randomly selected GCMs:", paste(SELECTED_GCMS, collapse = ", "))),
      br(),
      actionButton("run_model", "Run Model",
                   icon = icon("play"),
                   class = "btn-success btn-block",
                   style = "font-weight:bold; font-size:15px;"),
      br(),
      conditionalPanel(
        condition = "output.model_ready === true",
        tags$h6("Map Controls", style = "color:#ccc; text-transform:uppercase; letter-spacing:1px; margin-top:10px;"),
        sliderInput("threshold", "Suitability threshold",
                    min = 0, max = 1, value = 0.5, step = 0.01)
      )
    )
  ),

  dashboardBody(
    tags$head(tags$style(HTML("
      .content-wrapper, .right-side { background-color: #f5f7f5; }
      .box { border-top-color: #4CAF50 !important; }
      .small-box.bg-green  { background-color: #388e3c !important; }
      .small-box.bg-olive  { background-color: #558b2f !important; }
      .small-box.bg-teal   { background-color: #00695c !important; }
      .small-box.bg-light-blue { background-color: #0277bd !important; }
      .leaflet-container { border-radius: 4px; }
    "))),

    tabItems(

      # ── Tab 1 : Distribution Map ──────────────────────────────────────────
      tabItem("map",
        fluidRow(
          box(width = 12, status = "success", solidHeader = TRUE,
              title = tagList(icon("map-location-dot"),
                              " Predicted Habitat Suitability — California Poppy"),
              leafletOutput("suitability_map", height = "580px")
          )
        ),
        fluidRow(
          valueBoxOutput("auc_box",       width = 3),
          valueBoxOutput("tss_box",       width = 3),
          valueBoxOutput("n_occ_box",     width = 3),
          valueBoxOutput("threshold_box", width = 3)
        )
      ),

      # ── Tab 2 : Model Performance ─────────────────────────────────────────
      tabItem("perf",
        fluidRow(
          box(width = 6, status = "success", solidHeader = TRUE,
              title = "ROC Curve",
              plotlyOutput("roc_plot", height = "380px")),
          box(width = 6, status = "success", solidHeader = TRUE,
              title = "Predicted Score Distributions",
              plotlyOutput("score_dist_plot", height = "380px"))
        ),
        fluidRow(
          box(width = 12, status = "success", solidHeader = TRUE,
              title = "Diagnostics Table",
              DTOutput("diag_table"))
        )
      ),

      # ── Tab 3 : Response Curves ───────────────────────────────────────────
      tabItem("response",
        fluidRow(
          box(width = 12, status = "success", solidHeader = TRUE,
              title = "Response Curves (key bioclimatic predictors)",
              plotlyOutput("response_plot", height = "520px"))
        )
      ),

      # ── Tab 4 : Future Projections ──────────────────────────────────────
      tabItem("future",
        fluidRow(
          box(width = 4, status = "success", solidHeader = TRUE,
              title = "Projection Controls",
              selectInput("future_map_ssp", "Scenario map",
                          choices = paste0("RCP/SSP", ALL_SSPS),
                          selected = "RCP/SSP245"),
              tags$p(
                paste("Scenarios shown include all SSP pathways (RCP-style tiers):",
                      paste0("SSP", ALL_SSPS, collapse = ", ")),
                style = "margin-top:10px;"
              ),
              tags$p(
                paste("GCMs sampled once per app session:",
                      paste(SELECTED_GCMS, collapse = ", ")),
                style = "font-size:12px; color:#555;"
              )
          ),
          box(width = 8, status = "success", solidHeader = TRUE,
              title = "Future Ensemble Suitability Map",
              leafletOutput("future_map", height = "420px"))
        ),
        fluidRow(
          box(width = 6, status = "success", solidHeader = TRUE,
              title = "Suitable Fraction by Scenario and GCM",
              plotlyOutput("future_bar_plot", height = "330px")),
          box(width = 6, status = "success", solidHeader = TRUE,
              title = "Future Projection Summary",
              DTOutput("future_table"))
        )
      ),

      # ── Tab 5 : Variable Importance ───────────────────────────────────────
      tabItem("importance",
        fluidRow(
          box(width = 12, status = "success", solidHeader = TRUE,
              title = "Permutation Importance — AUC drop when variable is permuted",
              plotlyOutput("importance_plot", height = "520px"))
        )
      ),

      # ── Tab 6 : About ─────────────────────────────────────────────────────
      tabItem("about",
        fluidRow(
          box(width = 12, status = "success", solidHeader = TRUE,
              title = "About this Application",
              includeMarkdown("ABOUT.md"))
        )
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  wc_path <- Sys.getenv(
    "CALIPOPPY_WC_PATH",
    unset = file.path(tempdir(), "worldclim_data")
  )

  # Reactive container for all model outputs
  model_results <- reactiveVal(NULL)

  # Flag consumed by conditionalPanel in the UI
  output$model_ready <- reactive({ !is.null(model_results()) })
  outputOptions(output, "model_ready", suspendWhenHidden = FALSE)

  # ── Run SDM ──────────────────────────────────────────────────────────────
  observeEvent(input$run_model, {

    withProgress(message = "Building SDM…", value = 0, {

      set.seed(123)

      # 1. Occurrence data ------------------------------------------------
      incProgress(0.08, detail = "Fetching BIEN occurrence data…")
      occ <- tryCatch(
        BIEN::BIEN_occurrence_species(SPECIES),
        error = function(e) {
          showNotification(paste("BIEN error:", conditionMessage(e)),
                           type = "error", duration = 12)
          return(NULL)
        }
      )
      if (is.null(occ)) return(NULL)

      occ <- occ %>%
        filter(!is.na(latitude), !is.na(longitude)) %>%
        distinct(latitude, longitude, .keep_all = TRUE)

      occ_ca <- occ %>%
        filter(longitude >= -125, longitude <= -114,
               latitude  >=   32, latitude  <=   42)

      if (nrow(occ_ca) < 30) {
        showNotification("Too few California occurrences (< 30). Cannot fit model.",
                         type = "error", duration = 12)
        return(NULL)
      }

      # 2. WorldClim data ------------------------------------------------
      incProgress(0.15, detail = "Loading WorldClim v2.1 data…")
      wc <- tryCatch(
        geodata::worldclim_global(var = "bio", res = 2.5, path = wc_path),
        error = function(e) {
          showNotification(paste("WorldClim download error:", conditionMessage(e)),
                           type = "error", duration = 12)
          return(NULL)
        }
      )
      if (is.null(wc)) return(NULL)

      wc_ca      <- terra::crop(wc, CA_EXT)
      pred_names <- names(wc_ca)

      # 3. Background & presence data frames -----------------------------
      incProgress(0.10, detail = "Sampling background points…")
      bg_pts <- terra::spatSample(
        wc_ca[[1]], size = input$n_bg,
        method = "random", na.rm = TRUE, xy = TRUE, values = FALSE
      )
      bg_df   <- data.frame(x = bg_pts[, "x"], y = bg_pts[, "y"])
      pres_df <- data.frame(x = occ_ca$longitude, y = occ_ca$latitude)

      # 4. Extract climate values -----------------------------------------
      incProgress(0.10, detail = "Extracting climate values…")
      pres_vals <- as.data.frame(
        terra::extract(wc_ca, as.matrix(pres_df))
      )[, pred_names, drop = FALSE]
      bg_vals <- as.data.frame(
        terra::extract(wc_ca, as.matrix(bg_df))
      )[, pred_names, drop = FALSE]

      model_input <- bind_rows(
        cbind(pres_df, presence = 1L, pres_vals),
        cbind(bg_df,   presence = 0L, bg_vals)
      ) %>%
        filter(dplyr::if_all(dplyr::all_of(pred_names), ~ !is.na(.x)))

      # 5. Train / test split + maxnet fit --------------------------------
      incProgress(0.20, detail = "Training MaxEnt (maxnet) model…")
      pres_idx  <- which(model_input$presence == 1L)
      bg_idx    <- which(model_input$presence == 0L)
      train_p   <- sample(pres_idx, floor(input$train_frac * length(pres_idx)))
      train_b   <- sample(bg_idx,   floor(input$train_frac * length(bg_idx)))
      train_idx <- c(train_p, train_b)
      test_idx  <- setdiff(seq_len(nrow(model_input)), train_idx)

      train_df <- model_input[train_idx, ]
      test_df  <- model_input[test_idx,  ]
      x_train  <- train_df[, pred_names, drop = FALSE]
      p_train  <- train_df$presence

      mx <- maxnet::maxnet(
        p    = p_train,
        data = x_train,
        f    = maxnet::maxnet.formula(p_train, x_train, classes = input$classes)
      )

      # 6. Diagnostics ----------------------------------------------------
      incProgress(0.10, detail = "Computing model diagnostics…")
      x_test      <- test_df[, pred_names, drop = FALSE]
      test_labels <- test_df$presence
      test_score  <- as.numeric(predict(mx, x_test, type = "cloglog"))

      roc_obj  <- pROC::roc(response = test_labels, predictor = test_score,
                            quiet = TRUE)
      auc_val  <- as.numeric(pROC::auc(roc_obj))
      youden   <- pROC::coords(roc_obj, x = "best", best.method = "youden",
                               ret = c("threshold", "sensitivity", "specificity"))
      thr      <- as.numeric(youden["threshold"])

      pred_cl  <- as.integer(test_score >= thr)
      cm       <- table(Truth = factor(test_labels, 0:1),
                        Pred  = factor(pred_cl,     0:1))
      tn <- cm[1,1]; fp <- cm[1,2]; fn <- cm[2,1]; tp <- cm[2,2]
      sens <- tp / (tp + fn)
      spec <- tn / (tn + fp)
      acc  <- (tp + tn) / sum(cm)
      tss  <- sens + spec - 1

      diag_tbl <- data.frame(
        Metric = c("AUC", "Threshold (Youden)", "Sensitivity",
                   "Specificity", "Accuracy", "TSS"),
        Value  = round(c(auc_val, thr, sens, spec, acc, tss), 4)
      )

      # 7. Predict suitability raster ------------------------------------
      incProgress(0.12, detail = "Predicting suitability raster…")
      pred_ca <- raster::predict(
        raster::stack(wc_ca), mx, type = "cloglog"
      )

      # 8. Response curves -----------------------------------------------
      med        <- apply(model_input[, pred_names, drop = FALSE], 2,
                          median, na.rm = TRUE)
      vars_resp  <- intersect(c("bio1","bio5","bio6","bio12","bio15"),
                              pred_names)
      if (!length(vars_resp)) vars_resp <- head(pred_names, 5)

      response_df <- do.call(rbind, lapply(vars_resp, function(v) {
        xseq <- seq(min(model_input[[v]], na.rm = TRUE),
                    max(model_input[[v]], na.rm = TRUE),
                    length.out = 100)
        nd        <- as.data.frame(matrix(rep(med, each = length(xseq)),
                                          nrow = length(xseq)))
        names(nd) <- pred_names
        nd[[v]]   <- xseq
        label     <- if (v %in% names(BIO_LABELS)) BIO_LABELS[[v]] else v
        data.frame(variable = label, raw_var = v,
                   x = xseq,
                   suitability = as.numeric(predict(mx, nd, type = "cloglog")))
      }))

      # 9. Permutation importance ----------------------------------------
      incProgress(0.05, detail = "Computing permutation importance…")
      perm_imp <- bind_rows(lapply(pred_names, function(v) {
        xp      <- x_test
        xp[[v]] <- sample(xp[[v]])
        ap      <- as.numeric(pROC::auc(
          pROC::roc(test_labels,
                    as.numeric(predict(mx, xp, type = "cloglog")),
                    quiet = TRUE)
        ))
        lbl <- if (v %in% names(BIO_LABELS)) BIO_LABELS[[v]] else v
        data.frame(variable = lbl, raw_var = v,
                   importance = round(auc_val - ap, 5))
      })) %>% arrange(desc(importance))

      # 10. Future projections -------------------------------------------
      future_ensemble <- list()
      future_summary <- data.frame()
      if (isTRUE(input$run_future)) {
        incProgress(0.10, detail = "Downloading CMIP6 projections and projecting future ranges…")

        future_preds <- list()
        future_res <- 10

        for (gcm in SELECTED_GCMS) {
          for (ssp in ALL_SSPS) {
            incProgress(0.03 / (length(SELECTED_GCMS) * length(ALL_SSPS)),
                        detail = paste("Future:", gcm, "SSP", ssp))

            fut <- tryCatch(
              geodata::cmip6_world(
                model = gcm,
                ssp = ssp,
                time = input$future_time,
                var = "bio",
                res = future_res,
                path = wc_path
              ),
              error = function(e) {
                showNotification(
                  paste("Skipping", gcm, "SSP", ssp, "-", conditionMessage(e)),
                  type = "warning",
                  duration = 8
                )
                NULL
              }
            )
            if (is.null(fut)) next

            fut_ca <- terra::crop(fut, CA_EXT)
            fut_ca <- harmonize_bioc_names(fut_ca)

            missing_preds <- setdiff(pred_names, names(fut_ca))
            if (length(missing_preds) > 0) {
              showNotification(
                paste("Missing predictors for", gcm, "SSP", ssp),
                type = "warning",
                duration = 8
              )
              next
            }

            fut_ca <- fut_ca[[pred_names]]

            fut_pred <- raster::predict(raster::stack(fut_ca), mx, type = "cloglog")
            key <- paste(gcm, paste0("SSP", ssp), sep = "__")
            future_preds[[key]] <- fut_pred

            fvals <- raster::values(fut_pred)
            fbin <- raster::values(fut_pred > thr)
            future_summary <- bind_rows(
              future_summary,
              data.frame(
                gcm = gcm,
                scenario = paste0("RCP/SSP", ssp),
                period = input$future_time,
                mean_suitability = mean(fvals, na.rm = TRUE),
                suitable_fraction = mean(fbin == 1, na.rm = TRUE)
              )
            )
          }
        }

        for (ssp in ALL_SSPS) {
          keys <- grep(paste0("__SSP", ssp, "$"), names(future_preds), value = TRUE)
          if (!length(keys)) next
          future_ensemble[[paste0("RCP/SSP", ssp)]] <- raster::calc(
            raster::stack(future_preds[keys]),
            fun = mean,
            na.rm = TRUE
          )
        }
      }

      # Store everything --------------------------------------------------
      model_results(list(
        pred_ca     = pred_ca,
        pres_df     = pres_df,
        diag_tbl    = diag_tbl,
        roc_obj     = roc_obj,
        test_score  = test_score,
        test_labels = test_labels,
        threshold   = thr,
        response_df = response_df,
        perm_imp    = perm_imp,
        future_ensemble = future_ensemble,
        future_summary = future_summary,
        selected_gcms = SELECTED_GCMS,
        future_period = input$future_time,
        auc_val     = auc_val,
        tss         = tss,
        n_occ       = nrow(occ_ca)
      ))

      updateSliderInput(session, "threshold", value = round(thr, 2))
      showNotification(
        paste0("Model complete — AUC: ", round(auc_val, 3),
               "  |  TSS: ", round(tss, 3),
               if (isTRUE(input$run_future)) "  |  Future projections ready" else ""),
        type = "message", duration = 8
      )
    }) # withProgress
  }) # observeEvent run_model

  # ── Render initial / updated leaflet map ───────────────────────────────
  output$suitability_map <- renderLeaflet({
    res <- model_results()

    if (is.null(res)) {
      leaflet() %>%
        addProviderTiles("Esri.WorldShadedRelief") %>%
        setView(lng = -119.5, lat = 37, zoom = 6) %>%
        addControl(
          html = paste0(
            "<div style='background:rgba(255,255,255,0.85);padding:10px 14px;",
            "border-radius:6px;font-size:13px;'>",
            "<b>&#127807; California Poppy SDM</b><br>",
            "Configure settings in the sidebar<br>then click <b>Run Model</b>.",
            "</div>"
          ),
          position = "topright"
        )
    } else {
      pred   <- res$pred_ca
      pal    <- colorNumeric(viridis::viridis(100), raster::values(pred),
                             na.color = "transparent")

      suit_r <- pred
      suit_r[suit_r < input$threshold] <- NA
      pal_g  <- colorNumeric(c("forestgreen", "darkgreen"),
                             domain = c(input$threshold, 1),
                             na.color = "transparent")

      leaflet() %>%
        addProviderTiles("OpenStreetMap", group = "OSM") %>%
        addProviderTiles("Esri.WorldShadedRelief", group = "Relief") %>%
        addRasterImage(pred, colors = pal, opacity = 0.72,
                       group = "Suitability (continuous)") %>%
        addRasterImage(suit_r, colors = pal_g, opacity = 0.60,
                       group = "Suitable habitat (binary)") %>%
        addCircleMarkers(
          data      = res$pres_df, lng = ~x, lat = ~y,
          radius    = 3, color = "red", fillOpacity = 0.65, weight = 0,
          group     = "Occurrences",
          popup     = ~paste0("<b>Presence</b><br>Lon: ", round(x, 3),
                              "<br>Lat: ", round(y, 3))
        ) %>%
        addLegend(pal = pal, values = raster::values(pred),
                  title = "Suitability", position = "bottomright",
                  opacity = 0.85) %>%
        addLayersControl(
          baseGroups    = c("OSM", "Relief"),
          overlayGroups = c("Suitability (continuous)",
                            "Suitable habitat (binary)",
                            "Occurrences"),
          options       = layersControlOptions(collapsed = FALSE)
        ) %>%
        hideGroup("Suitable habitat (binary)")
    }
  })

  # Update only the binary layer when threshold slider moves
  observeEvent(input$threshold, {
    res <- model_results()
    req(res)
    suit_r <- res$pred_ca
    suit_r[suit_r < input$threshold] <- NA
    pal_g <- colorNumeric(c("forestgreen", "darkgreen"),
                          domain = c(input$threshold, 1),
                          na.color = "transparent")
    leafletProxy("suitability_map") %>%
      clearGroup("Suitable habitat (binary)") %>%
      addRasterImage(suit_r, colors = pal_g, opacity = 0.60,
                     group = "Suitable habitat (binary)")
  }, ignoreInit = TRUE)

  # ── Value boxes ─────────────────────────────────────────────────────────
  output$auc_box <- renderValueBox({
    res <- model_results()
    val <- if (!is.null(res)) round(res$auc_val, 3) else "—"
    valueBox(val, "AUC", icon = icon("chart-area"), color = "green")
  })
  output$tss_box <- renderValueBox({
    res <- model_results()
    val <- if (!is.null(res)) round(res$tss, 3) else "—"
    valueBox(val, "TSS", icon = icon("circle-check"), color = "olive")
  })
  output$n_occ_box <- renderValueBox({
    res <- model_results()
    val <- if (!is.null(res)) res$n_occ else "—"
    valueBox(val, "CA Occurrences", icon = icon("location-dot"), color = "teal")
  })
  output$threshold_box <- renderValueBox({
    res <- model_results()
    val <- if (!is.null(res)) round(input$threshold, 3) else "—"
    valueBox(val, "Threshold", icon = icon("sliders"), color = "light-blue")
  })

  # ── ROC curve ───────────────────────────────────────────────────────────
  output$roc_plot <- renderPlotly({
    res <- model_results(); req(res)
    roc_df <- data.frame(
      fpr = 1 - res$roc_obj$specificities,
      tpr = res$roc_obj$sensitivities
    )
    p <- ggplot(roc_df, aes(x = fpr, y = tpr)) +
      geom_line(color = "dodgerblue3", linewidth = 1) +
      geom_abline(intercept = 0, slope = 1, linetype = 2, color = "gray50") +
      coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
      labs(title   = sprintf("ROC curve  |  AUC = %.4f", res$auc_val),
           x = "False Positive Rate", y = "True Positive Rate") +
      theme_minimal(base_size = 13)
    ggplotly(p) %>% layout(showlegend = FALSE)
  })

  # ── Score distributions ─────────────────────────────────────────────────
  output$score_dist_plot <- renderPlotly({
    res <- model_results(); req(res)
    score_df <- data.frame(
      score = res$test_score,
      class = factor(res$test_labels, 0:1, c("Background", "Presence"))
    )
    p <- ggplot(score_df, aes(x = score, fill = class)) +
      geom_histogram(position = "identity", alpha = 0.45, bins = 40) +
      geom_vline(xintercept = input$threshold, linetype = 2, color = "black",
                 linewidth = 0.8) +
      scale_fill_manual(values = c("Background" = "gray55",
                                   "Presence"   = "firebrick3")) +
      labs(title = "Predicted suitability distributions",
           x = "cloglog score", y = "Count") +
      theme_minimal(base_size = 13)
    ggplotly(p)
  })

  # ── Diagnostics table ───────────────────────────────────────────────────
  output$diag_table <- renderDT({
    res <- model_results(); req(res)
    DT::datatable(
      res$diag_tbl,
      options  = list(dom = "t", pageLength = 10, ordering = FALSE),
      rownames = FALSE,
      class    = "compact stripe hover"
    ) %>%
      DT::formatStyle(
        "Value",
        background = DT::styleColorBar(c(0, 1), "#a5d6a7"),
        backgroundSize   = "100% 90%",
        backgroundRepeat = "no-repeat",
        backgroundPosition = "center"
      )
  })

  # ── Response curves ─────────────────────────────────────────────────────
  output$response_plot <- renderPlotly({
    res <- model_results(); req(res)
    p <- ggplot(res$response_df, aes(x = x, y = suitability)) +
      geom_line(color = "midnightblue", linewidth = 1) +
      facet_wrap(~ variable, scales = "free_x", ncol = 3) +
      ylim(0, 1) +
      labs(title = "Marginal response curves (other predictors held at median)",
           x = "Predictor value", y = "Predicted suitability") +
      theme_minimal(base_size = 12) +
      theme(strip.text = element_text(face = "bold", size = 9))
    ggplotly(p)
  })

  # ── Permutation importance ──────────────────────────────────────────────
  output$importance_plot <- renderPlotly({
    res <- model_results(); req(res)
    p <- ggplot(
      res$perm_imp,
      aes(x = reorder(variable, importance), y = importance,
          fill = importance,
          text = paste0("<b>", variable, "</b><br>AUC drop: ",
                        round(importance, 4)))
    ) +
      geom_col() +
      coord_flip() +
      scale_fill_viridis_c(option = "D", direction = -1) +
      labs(title = "Permutation importance",
           x = NULL, y = "AUC drop after permutation") +
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")
    ggplotly(p, tooltip = "text")
  })

  # ── Future map and summaries ────────────────────────────────────────────
  output$future_map <- renderLeaflet({
    res <- model_results(); req(res)
    req(length(res$future_ensemble) > 0)

    chosen <- input$future_map_ssp
    if (!(chosen %in% names(res$future_ensemble))) {
      chosen <- names(res$future_ensemble)[1]
    }
    pred <- res$future_ensemble[[chosen]]
    pal <- colorNumeric(viridis::viridis(100), raster::values(pred), na.color = "transparent")

    leaflet() %>%
      addProviderTiles("OpenStreetMap") %>%
      addRasterImage(pred, colors = pal, opacity = 0.75) %>%
      addLegend(pal = pal, values = raster::values(pred), title = chosen, position = "bottomright")
  })

  observeEvent(input$future_map_ssp, {
    res <- model_results()
    req(res)
    req(length(res$future_ensemble) > 0)
    req(input$future_map_ssp %in% names(res$future_ensemble))

    pred <- res$future_ensemble[[input$future_map_ssp]]
    pal <- colorNumeric(viridis::viridis(100), raster::values(pred), na.color = "transparent")

    leafletProxy("future_map") %>%
      clearImages() %>%
      clearControls() %>%
      addRasterImage(pred, colors = pal, opacity = 0.75) %>%
      addLegend(pal = pal, values = raster::values(pred), title = input$future_map_ssp, position = "bottomright")
  }, ignoreInit = TRUE)

  output$future_table <- renderDT({
    res <- model_results(); req(res)
    req(nrow(res$future_summary) > 0)
    DT::datatable(
      res$future_summary,
      options = list(pageLength = 8, autoWidth = TRUE),
      rownames = FALSE,
      class = "compact stripe hover"
    )
  })

  output$future_bar_plot <- renderPlotly({
    res <- model_results(); req(res)
    req(nrow(res$future_summary) > 0)
    p <- ggplot(
      res$future_summary,
      aes(x = scenario, y = suitable_fraction, fill = gcm,
          text = paste0("<b>", gcm, "</b><br>", scenario,
                        "<br>Suitable fraction: ", round(suitable_fraction, 4)))
    ) +
      geom_col(position = position_dodge(width = 0.8)) +
      labs(
        title = paste("Future suitable-area fraction", "(", res$future_period, ")"),
        x = "Scenario",
        y = "Fraction suitable"
      ) +
      theme_minimal(base_size = 13)
    ggplotly(p, tooltip = "text")
  })

} # server

# ---------------------------------------------------------------------------
shinyApp(ui, server)
