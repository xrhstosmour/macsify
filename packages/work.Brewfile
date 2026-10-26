# Packages for a work machine, on top of `base.Brewfile`. Add work-only packages below.
# The path and line arguments make an error inside it name `base.Brewfile`.
base_brewfile = File.join(__dir__, "base.Brewfile")
instance_eval(File.read(base_brewfile), base_brewfile, 1)

# Install applications.
cask 'claude'
cask 'datagrip'
