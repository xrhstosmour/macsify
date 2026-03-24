# Knowledge

## Search markdown files

Use `qmd` for searching your markdown knowledge base:

```bash
# Add markdown files to qmd context.
qmd collection add qmd://markdown "My Markdown Files"
qmd context add qmd://markdown "My Markdown Files"

# Build embeddings once.
qmd embed

# Fast keyword search.
qmd search "work log"

# Semantic search.
qmd vsearch "what did i do on January first week?"

# Best quality (hybrid + re-ranking).
qmd query "how I handle pagination in my projects?"
```
