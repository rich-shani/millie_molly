
;==============================================================================
; MILLIE AND MOLLY - AMIGA PORT
; assets.asm  -  Asset Tables and Compressed Tile Data
;==============================================================================
;
; Maps levels to visual asset sets (tileset + palette variants) and includes
; the compressed tile graphics for all five environment themes.
;
; The game has 9 "chapters", each with a fixed number of levels and a
; corresponding visual theme (tile set index 0-4).  The level selection
; system uses the LevelAssetSet table to look up which tile set to load for
; any given level number.
;
; Tile sets are compressed with the ZX0 algorithm (see zx0_faster.asm).
; At level load time, SetLevelAssets decompresses the appropriate .pak file
; into the TileSet buffer in Chip RAM, then GenTileMask builds the blitter
; mask data from it.
;
;==============================================================================


;==============================================================================
; Chapters  -  Chapter definition table
;
; Format: each chapter entry is 2 bytes:
;   byte 0 = number of levels in this chapter
;   byte 1 = tile asset set index (0-4) for this chapter
;
; Chapter listing:
;   Chapter 1 :  20 levels, tile set 0  (default / bats theme)
;   Chapter 2 :   5 levels, tile set 1
;   Chapter 3 :   5 levels, tile set 2
;   Chapter 4 :  15 levels, tile set 1
;   Chapter 5 :  15 levels, tile set 2
;   Chapter 6 :  10 levels, tile set 3
;   Chapter 7 :  10 levels, tile set 4
;   Chapter 8 :  10 levels, tile set 3
;   Chapter 9 :  10 levels, tile set 4
;
; Total levels: 20+5+5+15+15+10+10+10+10 = 100 levels
;==============================================================================

Chapters:
    dc.b    20,0    ; chapter 1: 20 levels, tile set 0 (bats theme)
    dc.b     5,1    ; chapter 2:  5 levels, tile set 1
    dc.b     5,2    ; chapter 3:  5 levels, tile set 2
    dc.b    15,1    ; chapter 4: 15 levels, tile set 1
    dc.b    15,2    ; chapter 5: 15 levels, tile set 2
    dc.b    10,3    ; chapter 6: 10 levels, tile set 3
    dc.b    10,4    ; chapter 7: 10 levels, tile set 4
    dc.b    10,3    ; chapter 8: 10 levels, tile set 3
    dc.b    10,4    ; chapter 9: 10 levels, tile set 4


;==============================================================================
; LevelAssetSet  -  Per-level tile set lookup table
;
; One byte per level (0-based).  The byte value is the tile set index (0-4)
; to use for that level.  This is a flat expansion of the Chapters table above:
;   levels   0-19 -> tile set 0   (20 levels)
;   levels  20-24 -> tile set 1   (5 levels)
;   levels  25-29 -> tile set 2   (5 levels)
;   levels  30-44 -> tile set 1   (15 levels)
;   levels  45-59 -> tile set 2   (15 levels)
;   levels  60-69 -> tile set 3   (10 levels)
;   levels  70-79 -> tile set 4   (10 levels)
;   levels  80-89 -> tile set 3   (10 levels)
;   levels  90-99 -> tile set 4   (10 levels)
;
; Used by SetLevelAssets:
;   move.b  (LevelAssetSet, LevelId.w), d0   -> tile set index in d0
;
; DCB.B  count,value  generates 'count' copies of 'value'.
; The EVEN directive ensures word alignment after the odd-length table.
;==============================================================================

LevelAssetSet:
    dcb.b   20,0    ; levels  0-19: tile set 0
    dcb.b    5,1    ; levels 20-24: tile set 1
    dcb.b    5,2    ; levels 25-29: tile set 2
    dcb.b   15,1    ; levels 30-44: tile set 1
    dcb.b   15,2    ; levels 45-59: tile set 2
    dcb.b   10,3    ; levels 60-69: tile set 3
    dcb.b   10,4    ; levels 70-79: tile set 4
    dcb.b   10,3    ; levels 80-89: tile set 3
    dcb.b   10,4    ; levels 90-99: tile set 4
    even            ; pad to word boundary for safe access after the table


;==============================================================================
; TileAssets  -  Pointers to compressed tile set data
;
; Five longword pointers, one per tile set variant (0-4).
; SetLevelAssets indexes this table to find the compressed source data:
;
;   add.w   d4,d4           ; index * 4  (longword entries)
;   add.w   d4,d4
;   lea     TileAssets,a0
;   move.l  (a0,d4.w),a0   ; a0 -> Tiles?_Packed
;   lea     TileSet,a1
;   bsr     zx0_decompress  ; decompress tile graphics into Chip RAM TileSet buffer
;
; The TileSet Chip RAM buffer is TILESET_SIZE bytes (TILESET_COUNT * TILE_SIZE).
;==============================================================================

TileAssets:
    dc.l    Tiles0_Packed           ; tile set 0 pointer
    dc.l    Tiles1_Packed           ; tile set 1 pointer
    dc.l    Tiles2_Packed           ; tile set 2 pointer
    dc.l    Tiles3_Packed           ; tile set 3 pointer
    dc.l    Tiles4_Packed           ; tile set 4 pointer


;==============================================================================
; Compressed tile graphics  (ZX0 format, included as raw binary)
;
; Each .pak file was compressed offline from the original raw bitplane tile
; data using the ZX0 compressor.  The zx0_decompress routine (zx0_faster.asm)
; decompresses them into the TileSet Chip RAM buffer at level load time.
;
; The labels mark the start of each compressed stream so TileAssets can point
; to them.  Note: the NEXT label implicitly marks the END of the previous one.
;
; Tile set 0 = default theme (used for the first 20 levels, "bats" chapter)
; Tile sets 1-4 = alternate visual themes for later chapters
;==============================================================================

Tiles0_Packed:
    incbin  "assets/tiles/Tiles_0.pak"  ; tile set 0, ZX0 compressed

Tiles1_Packed:
    incbin  "assets/tiles/Tiles_1.pak"  ; tile set 1, ZX0 compressed

Tiles2_Packed:
    incbin  "assets/tiles/Tiles_2.pak"  ; tile set 2, ZX0 compressed

Tiles3_Packed:
    incbin  "assets/tiles/Tiles_3.pak"  ; tile set 3, ZX0 compressed

Tiles4_Packed:
    incbin  "assets/tiles/Tiles_4.pak"  ; tile set 4, ZX0 compressed

    even    ; pad to word boundary after binary data
