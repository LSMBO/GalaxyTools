For a given glycopeptide sequence, this tool searches for the best combinations of sugar molecules to obtain the mass measured by the mass spectrometer.

To find the best combination, the theoretical mass of the peptide sequence is calculated and then all combinations are recursively generated until it goes past the measured mass. The results are ordered upon the lowest difference between the measured mass and the sum of the theoretical mass and the mass of the combination. The error in ppm is derived from that difference but there is usually only one possible combination, if any.

The sugar molecules can be:

| Sugar molecule       | Short name | Monoisotopic mass | Average mass |
|----------------------|------------|-------------------|--------------|
| Fucose               | Fuc        | 146.0579 Da       | 146.1414 Da  |
| GlcNAc               | HexNAc     | 203.0794 Da       | 203.1928 Da  |
| Mannose or Galactose | Hex        | 162.0528 Da       | 162.1409 Da  |
| Sialic acid          | NeuAc      | 291.0954 Da       | 291.2550 Da  |


