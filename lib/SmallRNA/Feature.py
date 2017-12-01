class FeatureItem:
  def __init__(self, name, sequence):
    self.Name = name
    self.Sequence = sequence

class FeatureGroup:
  def __init__(self):
    self.Features = []
    self.Queries = set()
    self.CoverageCount = {}
    self.Coverage = {}
