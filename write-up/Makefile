.SUFFIXES: .pdf .tex .bib $(SUFFIXES)

FLAGS := -quiet

TARGETS := semantics.pdf \
           proposal.pdf  \
           dissertation.pdf \
           paper.pdf

BUILD := build

# Add Bibligraphy at some point
DIS :=  myclass.cls \
        semantics_def.tex \
        titlepage.tex \
        declaration.tex \
        abstract.tex \
        introduction.tex \
        background.tex \
        implementation.tex \
        evaluation.tex \
        related_work.tex \
        conclusion.tex \
        ott_spec.tex \
        timings.tex \
        primitives.tex \
        eval_data.tex \
        timings_all.tex \
        timings.txt \
        trace.txt

DIS_DIR := dissertation
DIS := $(addprefix $(DIS_DIR)/,$(DIS))

SEM := semantics_def.tex \
       interpretation.tex \
       lemmas.tex \
       soundness.tex

SEM_DIR := semantics
SEM := $(addprefix $(SEM_DIR)/,$(SEM))

PAPER := intro.tex \
         lang_and_examples.tex \
         formal_system.tex \
         implementation.tex \
         discussion.tex \
         appendix.tex \
         lin_reg_timings.tex \
         l1_norm_min_timings.tex \
         kalman_timings.tex \
         ourbib.bib \
         llncs.cls \
         fig1.eps \
         splncs04.bst

PAPER_DIR := paper
PAPER := $(addprefix $(PAPER_DIR)/,$(PAPER))

BUILD_DIS := $(BUILD)/$(DIS_DIR)

.PHONY: all
all: $(TARGETS)

.SECONDEXPANSION:
$(TARGETS):%.pdf: $$*/$$*.tex | $(BUILD)
	cd $(dir $<) && latexmk -pdf -dvi- -ps- $(notdir $<) -shell-escape -output-directory=../$(BUILD) $(FLAGS)
	mv $(BUILD)/$@ $@

$(PAPER_DIR)/paper.tex: $(PAPER)
	touch $@

$(DIS_DIR)/dissertation.tex: $(DIS) | $(BUILD_DIS)
	touch $@

$(DIS_DIR)/semantics_def.tex: $(DIS_DIR)/semantics.ott
	ott -i $< -tex_show_meta false -tex_wrap false -o $@

$(SEM_DIR)/semantics.tex: $(SEM)
	touch $@

$(SEM_DIR)/semantics_def.tex: $(SEM_DIR)/semantics.ott
	ott -i $< -tex_show_meta false -tex_wrap false -o $@

$(BUILD_DIS): $(BUILD)
$(BUILD) $(BUILD_DIS): %:
	mkdir -p $@

.PHONY: clean
clean:
	rm -rf $(BUILD)
