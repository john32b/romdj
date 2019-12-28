## `romdj` Changelog

### v0.3.2
	- Preliminary support for entries with multiple files. Currently cannot build roms from multiroms, but the program will acknowledge and report them.
	- Fixed rom extension naming when building. Every rom extension will be read correctly from the entry data.
	
### v0.3.1
	- Bugfix, when using `nolang` or `regdel` sometimes it resulted in double spaces in filename

### V0.3
	- Renamed option `country` to `regkeep` (Region Keep)
	- Added option `regdel` (Region Delete)
	- When no more diskspace when building program will end gracefully
	- SevenZip, removed `-mmt` parameter as it is on by default

### v0.2.1
	- Added warning when loading dat files with multiple roms per entry

### v0.2
	- Support for skipping header in roms
	- Added `-nods` ( No deep-scan option )

### v0.1
	- First Release
