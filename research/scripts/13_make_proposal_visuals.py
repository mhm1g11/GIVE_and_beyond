"""
Create proposal visuals directly from the GIVE research outputs.

Outputs
-------
1. Monetised benefits by damage category
   - global benefits from EU-linked and Germany-linked methane abatement
   - domestic benefits within EU27 and Germany
   - converted from USD2005 to current EUR equivalent

2. Global mortality benefits only
   - global deaths avoided from EU-linked methane abatement
   - global deaths avoided from Germany-linked methane abatement
   - temperature-related and ozone respiratory mortality

The underlying Julia outputs are never modified.
Currency conversion occurs only in this reporting layer.

Run from repository root:

    python research\\scripts\\13_make_proposal_visuals.py
"""

from pathlib import Path
import re

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch


# =====================================================================
# Project paths
# =====================================================================

PROJECT_ROOT = Path(__file__).resolve().parents[2]

RESEARCH_DIR = PROJECT_ROOT / "research"
OUTPUT_DIR = RESEARCH_DIR / "outputs"
POLICY_DIR = OUTPUT_DIR / "policy_results"

MONETARY_TRIALS_PATH = (
    POLICY_DIR
    / "policy_monetary_expanded_trials.csv"
)

MORTALITY_SUMMARY_PATH = (
    POLICY_DIR
    / "policy_mortality_summary.csv"
)

FIGURE_DIR = (
    OUTPUT_DIR
    / "proposal_figures"
)

FIGURE_DIR.mkdir(
    parents=True,
    exist_ok=True
)


# =====================================================================
# Scenario identifiers
# =====================================================================

EU_SCENARIO = "EU27_import_regulation_mock"
DE_SCENARIO = "Germany_import_regulation_mock"


# =====================================================================
# USD2005 -> September 2026 EUR
#
# GIVE monetary results are USD2005.
#
# Conversion:
#
# USD2005
# × US CPI July 2026 / US CPI annual average 2005
# ÷ USD per EUR
#
# CPI-U 2005 annual average = 195.3
# CPI-U July 2026          = 333.918
#
# ECB reference exchange rate, 8 September 2026:
# 1 EUR = 1.1614 USD
#
# This gives approximately:
#
# 1 USD2005 = 1.4722 EUR2026
#
# Currency conversion is applied ONLY to displayed results.
# =====================================================================

CPI_US_2005 = 195.3
CPI_US_JUL_2026 = 333.918

USD_PER_EUR_8_SEP_2026 = 1.1614

USD2005_TO_EUR_2026 = (
    CPI_US_JUL_2026
    / CPI_US_2005
    / USD_PER_EUR_8_SEP_2026
)


# =====================================================================
# DIW Econ colour palette supplied for proposal figures
# =====================================================================

DIW_SALMON = "#D9A69F"
DIW_PURPLE = "#6C739C"
DIW_LIGHT_GREY = "#BABBB1"
DIW_DARK = "#424658"
DIW_GREEN = "#ADCBBA"
DIW_RED = "#C33F45"

DIW_TEXT = "#424658"
DIW_GRID = "#E6E6E2"
DIW_BACKGROUND = "#FFFFFF"


# Damage-category mapping

CATEGORY_COLOURS = {
    "slr_monetised":
        DIW_LIGHT_GREY,

    "energy_monetised":
        DIW_DARK,

    "agriculture_monetised":
        DIW_GREEN,

    "temperature_mortality_monetised":
        DIW_PURPLE,

    "ozone_mortality_monetised":
        DIW_RED,
}


CATEGORY_LABELS = {
    "slr_monetised":
        "Sea-level rise",

    "energy_monetised":
        "Energy",

    "agriculture_monetised":
        "Agriculture",

    "temperature_mortality_monetised":
        "Temperature mortality",

    "ozone_mortality_monetised":
        "Ozone respiratory mortality",
}


CATEGORY_ORDER = [
    "slr_monetised",
    "energy_monetised",
    "agriculture_monetised",
    "temperature_mortality_monetised",
    "ozone_mortality_monetised",
]


# =====================================================================
# Matplotlib style
# =====================================================================

plt.rcParams.update({
    "font.family": "Arial",
    "font.size": 10.5,
    "axes.titlesize": 12.5,
    "axes.titleweight": "bold",
    "axes.labelsize": 10.5,
    "xtick.labelsize": 10,
    "ytick.labelsize": 9.5,
    "legend.fontsize": 9.2,
    "figure.facecolor": DIW_BACKGROUND,
    "axes.facecolor": DIW_BACKGROUND,
    "axes.edgecolor": DIW_DARK,
    "axes.labelcolor": DIW_TEXT,
    "xtick.color": DIW_TEXT,
    "ytick.color": DIW_TEXT,
    "text.color": DIW_TEXT,
})


# =====================================================================
# General helpers
# =====================================================================

def normalise(text):
    """Normalise text for robust matching."""

    return re.sub(
        r"[^a-z0-9]+",
        "",
        str(text).lower()
    )


def find_column(
    df,
    candidates,
    required=True
):
    """Find a dataframe column using several possible names."""

    lookup = {
        normalise(col): col
        for col in df.columns
    }

    for candidate in candidates:

        key = normalise(candidate)

        if key in lookup:
            return lookup[key]

    if required:

        raise ValueError(
            "Could not identify required column.\n"
            f"Candidates: {candidates}\n"
            f"Available columns: {list(df.columns)}"
        )

    return None


def clean_axes(ax):
    """Apply consistent report-style formatting."""

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    ax.spines["left"].set_color(
        DIW_LIGHT_GREY
    )

    ax.spines["bottom"].set_color(
        DIW_LIGHT_GREY
    )

    ax.grid(
        axis="y",
        color=DIW_GRID,
        linewidth=0.7
    )

    ax.set_axisbelow(True)


def format_value(
    value,
    digits=1
):
    return f"{value:,.{digits}f}"


# =====================================================================
# Monetary data
# =====================================================================

def load_monetary_data():

    if not MONETARY_TRIALS_PATH.exists():

        raise FileNotFoundError(
            "Could not find monetary trial output:\n"
            f"{MONETARY_TRIALS_PATH}"
        )

    df = pd.read_csv(
        MONETARY_TRIALS_PATH
    )

    required = [
        "scenario_id",
        "benefit_geography",
        "trialnum",
        "metric",
        "benefit_usd2005",
    ]

    missing = [
        col
        for col in required
        if col not in df.columns
    ]

    if missing:

        raise ValueError(
            "Monetary trial file does not have the expected structure.\n"
            f"Missing: {missing}\n"
            f"Available columns: {list(df.columns)}"
        )

    df["benefit_usd2005"] = pd.to_numeric(
        df["benefit_usd2005"],
        errors="raise"
    )

    # Mean across currently available aligned trials.
    #
    # This automatically updates once a larger Monte Carlo sample
    # replaces the present five-trial proof-of-concept.

    means = (
        df
        .groupby(
            [
                "scenario_id",
                "benefit_geography",
                "metric",
            ],
            as_index=False
        )
        ["benefit_usd2005"]
        .mean()
    )

    means["benefit_eur2026"] = (
        means["benefit_usd2005"]
        * USD2005_TO_EUR_2026
    )

    return means


def monetary_value(
    means,
    scenario,
    geography,
    metric,
    default=0.0
):

    subset = means[
        (means["scenario_id"] == scenario)
        & (means["benefit_geography"] == geography)
        & (means["metric"] == metric)
    ]

    if subset.empty:
        return default

    if len(subset) != 1:

        raise ValueError(
            "Expected exactly one monetary value for:\n"
            f"{scenario}, {geography}, {metric}\n\n"
            f"{subset}"
        )

    return float(
        subset.iloc[0][
            "benefit_eur2026"
        ]
    )


# =====================================================================
# Bar-label logic
# =====================================================================

def should_label_segment(
    value,
    total,
    panel_max
):
    """
    Decide whether an in-bar label has enough visual space.

    Conditions:
    1. segment is at least 8% of its own stacked bar
    2. segment is at least 4.5% of the full panel y-range

    This prevents labels from being squeezed into tiny blocks.
    """

    if value <= 0:
        return False

    if total <= 0:
        return False

    relative_share = (
        value / total
    )

    panel_share = (
        value / panel_max
        if panel_max > 0
        else 0
    )

    return (
        relative_share >= 0.08
        and panel_share >= 0.045
    )


# =====================================================================
# Figure 1
# Monetised benefits
#
# Compact vertical layout:
#
# TOP:
#   global EU-linked vs Germany-linked
#
# BOTTOM:
#   EU27 domestic vs Germany domestic
#
# This makes much more efficient use of horizontal space than the
# previous side-by-side design.
# =====================================================================

def plot_monetised_benefits(
    means
):

    global_cases = [
        {
            "label":
                "EU-linked abatement",

            "scenario":
                EU_SCENARIO,

            "geography":
                "globe",
        },

        {
            "label":
                "Germany-linked abatement",

            "scenario":
                DE_SCENARIO,

            "geography":
                "globe",
        },
    ]

    domestic_cases = [
        {
            "label":
                "EU-linked → EU27",

            "scenario":
                EU_SCENARIO,

            "geography":
                "EU27",
        },

        {
            "label":
                "Germany-linked → Germany",

            "scenario":
                DE_SCENARIO,

            "geography":
                "DEU",
        },
    ]

    # ---------------------------------------------------------------
    # Figure
    # ---------------------------------------------------------------

    fig, axes = plt.subplots(
        2,
        1,
        figsize=(
            8.0,
            9.4
        )
    )

    fig.subplots_adjust(
        left=0.13,
        right=0.96,
        top=0.84,
        bottom=0.19,
        hspace=0.52
    )

    fig.text(
        0.13,
        0.955,
        "Monetised benefits of methane abatement",
        fontsize=18,
        fontweight="bold",
        ha="left",
        va="top",
        color=DIW_TEXT
    )

    fig.text(
        0.13,
        0.919,
        (
            "Climate and ozone-health benefits attributable to "
            "EU- and Germany-linked methane reductions"
        ),
        fontsize=10.8,
        ha="left",
        va="top",
        color=DIW_DARK
    )

    # ---------------------------------------------------------------
    # Panel function
    # ---------------------------------------------------------------

    def draw_panel(
        ax,
        cases,
        scale,
        title,
        ylabel,
    ):

        clean_axes(
            ax
        )

        x = np.arange(
            len(cases)
        )

        width = 0.52

        # -----------------------------------------------------------
        # Calculate full data matrix first.
        # -----------------------------------------------------------

        data = {}

        for metric in CATEGORY_ORDER:

            data[metric] = np.asarray([
                monetary_value(
                    means,
                    case["scenario"],
                    case["geography"],
                    metric,
                    default=0.0
                )
                / scale
                for case in cases
            ])

        stack_totals = np.zeros(
            len(cases)
        )

        for metric in CATEGORY_ORDER:
            stack_totals += data[metric]

        official_totals = np.asarray([
            monetary_value(
                means,
                case["scenario"],
                case["geography"],
                "expanded_total",
                default=0.0
            )
            / scale
            for case in cases
        ])

        panel_max = max(
            max(stack_totals),
            max(official_totals)
        )

        ax.set_ylim(
            0,
            panel_max * 1.19
        )

        # -----------------------------------------------------------
        # Draw stack
        # -----------------------------------------------------------

        bottoms = np.zeros(
            len(cases)
        )

        for metric in CATEGORY_ORDER:

            values = data[
                metric
            ]

            bars = ax.bar(
                x,
                values,
                bottom=bottoms,
                width=width,
                color=CATEGORY_COLOURS[
                    metric
                ],
                edgecolor="white",
                linewidth=0.8
            )

            # -------------------------------------------------------
            # Internal labels only when there is enough space.
            # -------------------------------------------------------

            for i, bar in enumerate(
                bars
            ):

                value = values[i]

                if not should_label_segment(
                    value=value,
                    total=stack_totals[i],
                    panel_max=panel_max
                ):
                    continue

                digits = (
                    1
                    if value < 100
                    else 0
                )

                ax.text(
                    bar.get_x()
                    + bar.get_width() / 2,

                    bottoms[i]
                    + value / 2,

                    format_value(
                        value,
                        digits
                    ),

                    ha="center",
                    va="center",

                    fontsize=9.3,
                    color="white",
                    fontweight="bold"
                )

            bottoms += values

        # -----------------------------------------------------------
        # Total labels
        # -----------------------------------------------------------

        for i, total in enumerate(
            official_totals
        ):

            digits = (
                1
                if total < 100
                else 0
            )

            ax.text(
                x[i],
                max(
                    total,
                    stack_totals[i]
                )
                + panel_max * 0.035,

                format_value(
                    total,
                    digits
                ),

                ha="center",
                va="bottom",
                fontsize=11.5,
                color=DIW_TEXT,
                fontweight="bold"
            )

        # -----------------------------------------------------------
        # Axes
        # -----------------------------------------------------------

        ax.set_xticks(
            x
        )

        ax.set_xticklabels(
            [
                case["label"]
                for case in cases
            ]
        )

        ax.tick_params(
            axis="x",
            pad=8
        )

        ax.set_ylabel(
            ylabel
        )

        ax.set_title(
            title,
            loc="left",
            pad=10
        )

    # ---------------------------------------------------------------
    # Global benefits
    # ---------------------------------------------------------------

    draw_panel(
        axes[0],
        global_cases,
        scale=1e9,
        title="Global benefits",
        ylabel="Billion EUR"
    )

    # ---------------------------------------------------------------
    # Domestic benefits
    # ---------------------------------------------------------------

    draw_panel(
        axes[1],
        domestic_cases,
        scale=1e6,
        title="Benefits within the regulating market",
        ylabel="Million EUR"
    )

    # ---------------------------------------------------------------
    # Legend
    # ---------------------------------------------------------------

    handles = [
        Patch(
            facecolor=CATEGORY_COLOURS[
                metric
            ],
            label=CATEGORY_LABELS[
                metric
            ]
        )
        for metric in CATEGORY_ORDER
    ]

    fig.legend(
        handles=handles,
        loc="lower center",
        bbox_to_anchor=(
            0.5,
            0.102
        ),
        ncol=3,
        frameon=False,
        columnspacing=1.5,
        handlelength=1.25
    )

    # ---------------------------------------------------------------
    # Notes
    # ---------------------------------------------------------------

    fig.text(
        0.13,
        0.057,
        (
            "Notes: values are means across the currently available "
            "aligned GIVE trials. Agriculture is not estimated for "
            "EU27 and German domestic benefits. Total labels include "
            "the small GIVE reconciliation residual."
        ),
        fontsize=8.1,
        color=DIW_DARK,
        ha="left"
    )

    fig.text(
        0.13,
        0.026,
        (
            "Currency: USD2005 converted to 2026 EUR using US CPI-U "
            f"({CPI_US_2005:.1f} → {CPI_US_JUL_2026:.3f}) and the "
            f"ECB reference rate of {USD_PER_EUR_8_SEP_2026:.4f} "
            "USD/EUR on 8 September 2026."
        ),
        fontsize=7.9,
        color=DIW_DARK,
        ha="left"
    )

    # ---------------------------------------------------------------
    # Save
    # ---------------------------------------------------------------

    png_path = (
        FIGURE_DIR
        / "01_monetised_benefits_eur2026.png"
    )

    svg_path = (
        FIGURE_DIR
        / "01_monetised_benefits_eur2026.svg"
    )

    fig.savefig(
        png_path,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    fig.savefig(
        svg_path,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close(
        fig
    )

    return (
        png_path,
        svg_path
    )


# =====================================================================
# Physical mortality data loader
# =====================================================================

def load_mortality_data():

    if not MORTALITY_SUMMARY_PATH.exists():

        raise FileNotFoundError(
            "Could not find physical mortality output:\n"
            f"{MORTALITY_SUMMARY_PATH}"
        )

    df = pd.read_csv(
        MORTALITY_SUMMARY_PATH
    )

    scenario_col = find_column(
        df,
        [
            "scenario_id",
            "scenario",
        ]
    )

    geography_col = find_column(
        df,
        [
            "benefit_geography",
            "geography",
            "region",
        ]
    )

    pathway_col = find_column(
        df,
        [
            "pathway",
            "mortality_pathway",
            "metric",
            "impact",
        ],
        required=False
    )

    # ---------------------------------------------------------------
    # Long format
    # ---------------------------------------------------------------

    if pathway_col is not None:

        value_col = find_column(
            df,
            [
                "avoided_deaths",
                "deaths_avoided",
                "cumulative_avoided_deaths",
                "cumulative_deaths_avoided",
                "deaths",
                "value",
            ],
            required=False
        )

        if value_col is None:

            candidates = [
                col
                for col in df.columns
                if (
                    "death" in normalise(
                        col
                    )
                    and
                    pd.api.types.is_numeric_dtype(
                        df[col]
                    )
                )
            ]

            if len(candidates) == 1:

                value_col = (
                    candidates[0]
                )

            else:

                raise ValueError(
                    "Could not identify mortality value column.\n"
                    f"Available columns: {list(df.columns)}"
                )

        return pd.DataFrame({
            "scenario_id":
                df[
                    scenario_col
                ].astype(str),

            "geography":
                df[
                    geography_col
                ].astype(str),

            "pathway":
                df[
                    pathway_col
                ].astype(str),

            "deaths":
                pd.to_numeric(
                    df[
                        value_col
                    ],
                    errors="raise"
                ),
        })

    # ---------------------------------------------------------------
    # Wide-format fallback
    # ---------------------------------------------------------------

    temp_cols = [
        col
        for col in df.columns
        if (
            "temperature"
            in normalise(col)
            and
            "death"
            in normalise(col)
        )
    ]

    ozone_cols = [
        col
        for col in df.columns
        if (
            "ozone"
            in normalise(col)
            and
            "death"
            in normalise(col)
        )
    ]

    if (
        len(temp_cols) != 1
        or len(ozone_cols) != 1
    ):

        raise ValueError(
            "Mortality summary structure was not recognised.\n"
            f"Available columns: {list(df.columns)}"
        )

    rows = []

    for _, row in df.iterrows():

        rows.append({
            "scenario_id":
                str(
                    row[
                        scenario_col
                    ]
                ),

            "geography":
                str(
                    row[
                        geography_col
                    ]
                ),

            "pathway":
                "temperature",

            "deaths":
                float(
                    row[
                        temp_cols[0]
                    ]
                ),
        })

        rows.append({
            "scenario_id":
                str(
                    row[
                        scenario_col
                    ]
                ),

            "geography":
                str(
                    row[
                        geography_col
                    ]
                ),

            "pathway":
                "ozone_respiratory",

            "deaths":
                float(
                    row[
                        ozone_cols[0]
                    ]
                ),
        })

    return pd.DataFrame(
        rows
    )


def physical_mortality_value(
    mortality,
    scenario,
    pathway
):

    geography = (
        mortality[
            "geography"
        ]
        .astype(str)
        .str.lower()
        .str.strip()
    )

    global_mask = (
        geography.isin([
            "globe",
            "global",
            "world",
        ])
    )

    pathway_values = (
        mortality[
            "pathway"
        ]
        .astype(str)
        .str.lower()
    )

    if pathway == "temperature":

        pathway_mask = (
            pathway_values
            .str.contains(
                "temperature",
                regex=False
            )
        )

    elif pathway == "ozone":

        pathway_mask = (
            pathway_values
            .str.contains(
                "ozone",
                regex=False
            )
        )

    else:

        raise ValueError(
            f"Unknown pathway: {pathway}"
        )

    subset = mortality[
        (
            mortality[
                "scenario_id"
            ]
            == scenario
        )
        & global_mask
        & pathway_mask
    ]

    if subset.empty:

        raise ValueError(
            "Could not locate global physical mortality value for:\n"
            f"Scenario: {scenario}\n"
            f"Pathway: {pathway}\n\n"
            "Available scenarios:\n"
            f"{sorted(mortality['scenario_id'].unique())}\n\n"
            "Available geographies:\n"
            f"{sorted(mortality['geography'].unique())}\n\n"
            "Available pathways:\n"
            f"{sorted(mortality['pathway'].unique())}"
        )

    return float(
        subset[
            "deaths"
        ].sum()
    )


# =====================================================================
# Figure 2
# GLOBAL physical mortality only
# =====================================================================

def plot_global_mortality(
    mortality
):

    cases = [
        {
            "label":
                "EU-linked abatement",

            "scenario":
                EU_SCENARIO,
        },

        {
            "label":
                "Germany-linked abatement",

            "scenario":
                DE_SCENARIO,
        },
    ]

    temperature = np.asarray([
        physical_mortality_value(
            mortality,
            case[
                "scenario"
            ],
            "temperature"
        )
        for case in cases
    ])

    ozone = np.asarray([
        physical_mortality_value(
            mortality,
            case[
                "scenario"
            ],
            "ozone"
        )
        for case in cases
    ])

    totals = (
        temperature
        + ozone
    )

    max_total = max(
        totals
    )

    # ---------------------------------------------------------------
    # Compact figure
    # ---------------------------------------------------------------

    fig, ax = plt.subplots(
        figsize=(
            7.3,
            5.7
        )
    )

    fig.subplots_adjust(
        left=0.14,
        right=0.96,
        top=0.79,
        bottom=0.22
    )

    fig.text(
        0.14,
        0.95,
        "Global mortality benefits of methane abatement",
        fontsize=17.5,
        fontweight="bold",
        ha="left",
        va="top",
        color=DIW_TEXT
    )

    fig.text(
        0.14,
        0.907,
        "Avoided deaths globally through 2100",
        fontsize=10.8,
        ha="left",
        va="top",
        color=DIW_DARK
    )

    clean_axes(
        ax
    )

    x = np.arange(
        len(cases)
    )

    width = 0.48

    # ---------------------------------------------------------------
    # Bars
    # ---------------------------------------------------------------

    ax.bar(
        x,
        temperature,
        width=width,
        color=DIW_PURPLE,
        edgecolor="white",
        linewidth=0.8,
        label="Temperature-related mortality"
    )

    ax.bar(
        x,
        ozone,
        width=width,
        bottom=temperature,
        color=DIW_RED,
        edgecolor="white",
        linewidth=0.8,
        label="Ozone respiratory mortality"
    )

    ax.set_ylim(
        0,
        max_total * 1.17
    )

    # ---------------------------------------------------------------
    # Labels
    # ---------------------------------------------------------------

    for i in range(
        len(cases)
    ):

        total = totals[i]

        if should_label_segment(
            temperature[i],
            total,
            max_total
        ):

            ax.text(
                x[i],
                temperature[i] / 2,
                f"{temperature[i]:,.0f}",
                ha="center",
                va="center",
                color="white",
                fontsize=10,
                fontweight="bold"
            )

        if should_label_segment(
            ozone[i],
            total,
            max_total
        ):

            ax.text(
                x[i],
                temperature[i]
                + ozone[i] / 2,
                f"{ozone[i]:,.0f}",
                ha="center",
                va="center",
                color="white",
                fontsize=10,
                fontweight="bold"
            )

        ax.text(
            x[i],
            total
            + max_total * 0.03,
            f"{total:,.0f}",
            ha="center",
            va="bottom",
            fontsize=11.5,
            fontweight="bold",
            color=DIW_TEXT
        )

    # ---------------------------------------------------------------
    # Axes
    # ---------------------------------------------------------------

    ax.set_xticks(
        x
    )

    ax.set_xticklabels(
        [
            case[
                "label"
            ]
            for case in cases
        ]
    )

    ax.tick_params(
        axis="x",
        pad=8
    )

    ax.set_ylabel(
        "Global deaths avoided"
    )

    ax.legend(
        loc="upper right",
        frameon=False
    )

    # ---------------------------------------------------------------
    # Notes
    # ---------------------------------------------------------------

    fig.text(
        0.14,
        0.075,
        (
            "Notes: global mortality effects only. Temperature mortality "
            "is the net temperature-related mortality response from GIVE. "
            "Ozone respiratory mortality uses the GIVE-first McDuffie extension."
        ),
        fontsize=8.1,
        color=DIW_DARK,
        ha="left"
    )

    fig.text(
        0.14,
        0.041,
        (
            "Current figures use the central ozone-health calibration. "
            "Monte Carlo uncertainty is not shown."
        ),
        fontsize=8.0,
        color=DIW_DARK,
        ha="left"
    )

    # ---------------------------------------------------------------
    # Save
    # ---------------------------------------------------------------

    png_path = (
        FIGURE_DIR
        / "02_global_mortality_benefits.png"
    )

    svg_path = (
        FIGURE_DIR
        / "02_global_mortality_benefits.svg"
    )

    fig.savefig(
        png_path,
        dpi=300,
        bbox_inches="tight",
        facecolor="white"
    )

    fig.savefig(
        svg_path,
        bbox_inches="tight",
        facecolor="white"
    )

    plt.close(
        fig
    )

    return (
        png_path,
        svg_path
    )


# =====================================================================
# Save exact underlying proposal values
# =====================================================================

def save_plot_data(
    monetary_means,
    mortality
):

    monetary_output = (
        FIGURE_DIR
        / "proposal_monetary_values_eur2026.csv"
    )

    mortality_output = (
        FIGURE_DIR
        / "proposal_global_mortality_values.csv"
    )

    relevant = monetary_means[
        monetary_means[
            "scenario_id"
        ].isin([
            EU_SCENARIO,
            DE_SCENARIO,
        ])
    ].copy()

    relevant.to_csv(
        monetary_output,
        index=False
    )

    rows = []

    for scenario in [
        EU_SCENARIO,
        DE_SCENARIO,
    ]:

        temp = physical_mortality_value(
            mortality,
            scenario,
            "temperature"
        )

        ozone = physical_mortality_value(
            mortality,
            scenario,
            "ozone"
        )

        rows.append({
            "scenario_id":
                scenario,

            "temperature_deaths_avoided_global":
                temp,

            "ozone_respiratory_deaths_avoided_global":
                ozone,

            "combined_quantified_deaths_avoided_global":
                temp + ozone,
        })

    pd.DataFrame(
        rows
    ).to_csv(
        mortality_output,
        index=False
    )

    return (
        monetary_output,
        mortality_output
    )


# =====================================================================
# Main
# =====================================================================

def main():

    print(
        "CREATING GIVE PROPOSAL VISUALS"
    )

    print(
        "=============================="
    )

    print()

    print(
        "Project root:"
    )

    print(
        f"  {PROJECT_ROOT}"
    )

    print()

    print(
        "USD2005 -> 2026 EUR"
    )

    print(
        "-------------------"
    )

    print(
        f"CPI-U 2005:        {CPI_US_2005}"
    )

    print(
        f"CPI-U July 2026:   {CPI_US_JUL_2026}"
    )

    print(
        "ECB rate:          "
        f"{USD_PER_EUR_8_SEP_2026} USD per EUR"
    )

    print(
        "Conversion factor: "
        f"{USD2005_TO_EUR_2026:.6f}"
    )

    print()

    print(
        "Colour palette:"
    )

    print(
        f"  Sea-level rise:       {DIW_LIGHT_GREY}"
    )

    print(
        f"  Energy:               {DIW_DARK}"
    )

    print(
        f"  Agriculture:          {DIW_GREEN}"
    )

    print(
        f"  Temperature mortality:{DIW_PURPLE}"
    )

    print(
        f"  Ozone mortality:      {DIW_RED}"
    )

    print()

    # ---------------------------------------------------------------
    # Load
    # ---------------------------------------------------------------

    monetary_means = (
        load_monetary_data()
    )

    mortality = (
        load_mortality_data()
    )

    # ---------------------------------------------------------------
    # Draw
    # ---------------------------------------------------------------

    money_png, money_svg = (
        plot_monetised_benefits(
            monetary_means
        )
    )

    mortality_png, mortality_svg = (
        plot_global_mortality(
            mortality
        )
    )

    money_csv, mortality_csv = (
        save_plot_data(
            monetary_means,
            mortality
        )
    )

    # ---------------------------------------------------------------
    # Report
    # ---------------------------------------------------------------

    print(
        "Figures created successfully."
    )

    print()

    print(
        "Monetised benefits:"
    )

    print(
        f"  {money_png}"
    )

    print(
        f"  {money_svg}"
    )

    print()

    print(
        "Global mortality:"
    )

    print(
        f"  {mortality_png}"
    )

    print(
        f"  {mortality_svg}"
    )

    print()

    print(
        "Underlying proposal data:"
    )

    print(
        f"  {money_csv}"
    )

    print(
        f"  {mortality_csv}"
    )


if __name__ == "__main__":

    main()