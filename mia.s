; ---- Macros ----

; FRAME pairs, locals, args — prologue: fp/lr, then `pairs` register pairs from x19 (stored by Lpro<pairs>), then locals; with args, x19 = x0 and x20 = x1.
.macro FRAME pairs, locals=0, args=0
	.if (\locals) % 16
	.error "FRAME locals must keep sp 16-byte aligned"
	.endif
	stp	x29, x30, [sp, #-16]!
	.if \pairs
	.if \args
	bl	Lpro\pairs\()m
	.else
	bl	Lpro\pairs
	.endif
	.else
	mov	x29, sp
	.endif
	.if (\locals) > 4095
	sub	sp, sp, #((\locals) >> 12), lsl #12
	.endif
	.if (\locals) & 4095
	sub	sp, sp, #((\locals) & 4095)
	.endif
.endm

; ENTRY name — a function called from outside (AppKit, GCD, pthreads): its body Lname runs with x28 = G, x27 = B.
.macro ENTRY name
\name:
	adr	x16, L\name
	b	tramp
L\name:
.endm

; VM program — the function's body is a UI program, its arguments in locals a-h; VMENTRY name, program: the same for a method.
.macro VM program
	ADDR	x9, \program
	b	vm_run
.endm
.macro VMENTRY name, program
\name:
	ADDR	x9, \program
	b	vm_entry
.endm
; VMT / VMTENTRY name — the same with the program right after, in the code (it ends with OP_END and .p2align 2).
.macro VMT
	adr	x9, Lvmt\@
	b	vm_run
Lvmt\@:
.endm
.macro VMTENTRY name
\name:
	adr	x9, Lvmt\@
	b	vm_entry
Lvmt\@:
.endm

; ADDR reg, sym — address of a symbol in this file.
.macro ADDR reg, sym
	adrp	\reg, \sym@PAGE
	add	\reg, \reg, \sym@PAGEOFF
.endm

; CLASS reg, name — an Objective-C class, from the registry.
.macro CLASS reg, name
	ldr	\reg, [x27, #C_\name]
.endm

; SEND / SENDT sel — objc_msgSend with a selector from the registry (SENDT: a tail call).
.macro SEND sel                          ; through the selector's stub, if it has one
	.ifdef	L\sel
	bl	L\sel
	.else
	ldr	x1, [x27, #\sel]
	bl	_objc_msgSend
	.endif
.endm
.macro SENDT sel
	.ifdef	L\sel
	b	L\sel
	.else
	ldr	x1, [x27, #\sel]
	b	_objc_msgSend
	.endif
.endm

; GADDR reg, label — address of a label in G's data, from x28.
.macro GADDR reg, label
	adrp	\reg, \label@PAGE
	add	\reg, \reg, \label@PAGEOFF
.endm

; BADDR reg, offset — address of a B buffer, from x27.
.macro BADDR reg, off
	.if (\off) < 4096
	add	\reg, x27, #(\off)
	.elseif ((\off) & 4095) == 0
	add	\reg, x27, #((\off) >> 12), lsl #12
	.else
	add	\reg, x27, #((\off) >> 12), lsl #12
	add	\reg, \reg, #((\off) & 4095)
	.endif
.endm

; ADDO reg, base, off — reg = base + off, for offsets past an immediate's 4 KiB.
.macro ADDO reg, base, off
	.if (\off) < 4096
	add	\reg, \base, #(\off)
	.else
	add	\reg, \base, #((\off) >> 12), lsl #12
	.if (\off) & 4095
	add	\reg, \reg, #((\off) & 4095)
	.endif
	.endif
.endm

; TYPE reg, a, b, c, d — a four-character code as it reads from memory, e.g. a box type.
.macro TYPE reg, a, b, c, d
	mov	\reg, #((\a) | (\b) << 8)
	movk	\reg, #((\c) | (\d) << 8), lsl #16
.endm

; MOVL reg, value — a constant of up to 32 bits.
.macro MOVL reg, v
	mov	\reg, #((\v) & 0xffff)
	.if ((\v) >> 16) & 0xffff
	movk	\reg, #(((\v) >> 16) & 0xffff), lsl #16
	.endif
.endm

; CSTR reg, text — a C string literal, kept after G.
.macro CSTR reg, text
	.pushsection __DATA,__data
Lc\@:	.asciz	"\text"
	.popsection
	adrp	\reg, Lc\@@PAGE
	add	\reg, \reg, Lc\@@PAGEOFF
.endm

; CALLF / JUMPF name — call or tail-call a registry function that has no stub (one call site).
.macro CALLF name
	ldr	x16, [x27, #F_\name]
	blr	x16
.endm
.macro JUMPF name
	ldr	x16, [x27, #F_\name]
	br	x16
.endm

; LOCK / UNLOCK — the lock guarding the playlist slots and visitorData.
.macro LOCK
	bl	lock
.endm
.macro UNLOCK
	bl	unlock
.endm

; MAINQ reg — the main dispatch queue.
.macro MAINQ reg
	ldr	\reg, [x27, #F__dispatch_main_q]
.endm

; WORKQ — the global user-initiated queue in x0.
.macro WORKQ
	ldr	x0, [x28, #G_WORKQ]
.endm

; UI programs for ui_run (vm_run).
.macro OP_END
	.byte	0
.endm
.macro STO slot
	.byte	1, (\slot) >> 3
.endm
.macro LD slot
	.byte	2, (\slot) >> 3
.endm
.macro ADDV
	.byte	3
.endm
.macro CLS name
	.byte	4, (C_\name - B_REG) >> 3
.endm
.macro MSG sel, kinds=""                 ; the commonest kinds have operations of their own
	.set	Lmk, 6
	.ifc	"\kinds", "="
	.set	Lmk, 64
	.endif
	.ifc	"\kinds", "I"
	.set	Lmk, 65
	.endif
	.ifc	"\kinds", "O"
	.set	Lmk, 66
	.endif
	.ifc	"\kinds", ""
	.set	Lmk, 67
	.endif
	.byte	Lmk, (\sel - B_SEL) >> 3
	.if	Lmk == 6
	.asciz	"\kinds"
	.endif
.endm
.macro CALL fn, kinds=""
	.byte	5, (\fn - B_REG) >> 3
	.asciz	"\kinds"
.endm
.macro NCALL fn, kinds=""                ; a function of this file
	.byte	11
	.long	\fn - Lvm_base
	.asciz	"\kinds"
.endm
.macro JUMP op, label                     ; a jump of at most 127 bytes either way to a HERE, checked as it assembles
	.byte	\op
	.ifdef	\label
	.if	(. + 1 - \label) > 128
	.error	"backward jump too far"
	.endif
	.else
	.ifndef	\label\()_far
\label\()_far:
	.endif
	.endif
	.byte	\label - . - 1
.endm
.macro HERE label
\label:
	.ifdef	\label\()_far
	.if	(\label - \label\()_far) > 128
	.error	"forward jump too far"
	.endif
	.endif
.endm
.macro JZ label
	JUMP	12, \label
.endm
.macro JNZ label
	JUMP	13, \label
.endm
.macro JMP label
	JUMP	14, \label
.endm
.macro LW field                          ; a G word into current
	.byte	15, (\field) >> 2
.endm
.macro SW field
	.byte	16, (\field) >> 2
.endm
.macro IMM n
	.byte	17, \n
.endm
.macro ADDI n
	.byte	18, \n
.endm
.macro EQ n                              ; current = current == n
	.byte	19, \n
.endm
.macro LT n                              ; current = current < n
	.byte	20, \n
.endm
.macro BIT n                             ; current = bit n of current
	.byte	21, \n
.endm
.macro SHL n
	.byte	22, \n
.endm
.macro SL n                              ; current into local n (0-7: a-h)
	.byte	23 + \n
.endm
.macro GL n
	.byte	31 + \n
.endm
.macro EQL n                             ; current = current == local n
	.byte	39 + \n
.endm
.macro ADDL n
	.byte	47 + \n
.endm
.macro SUBL n
	.byte	55 + \n
.endm
.macro LDX off                           ; current = the xword, word or byte at current + off
	.byte	68
	.short	\off
.endm
.macro LDW off
	.byte	69
	.short	\off
.endm
.macro LDB off
	.byte	70
	.short	\off
.endm
.macro ADDH n                            ; current += n, up to 65535
	.byte	71
	.short	\n
.endm
.macro MULH n
	.byte	72
	.short	\n
.endm
.macro DIVH n
	.byte	73
	.short	\n
.endm
.macro ANDH n
	.byte	74
	.short	\n
.endm
.macro LDEW field                        ; a B word into current, and back
	.byte	79
	.short	\field
.endm
.macro STEW field
	.byte	80
	.short	\field
.endm
.macro FL n                              ; f = local n (a double)
	.byte	82, \n
.endm
.macro FS n
	.byte	83, \n
.endm
.macro FK k                              ; f = k / 16
	.byte	84
	.short	\k
.endm
.macro FI                                ; f = current
	.byte	85
.endm
.macro FT                                ; current = f, truncated
	.byte	86
.endm
.macro FOP op, n                         ; f = f op local n: 0 +, 1 -, 2 *, 3 /, 4 min, 5 max, 6 current = f > it, 7 ceil, 8 floor, 9 |f - it|
	.byte	87, \op, \n
.endm
.macro FOPK op, k                        ; the same with k / 16
	.byte	88, \op
	.short	\k
.endm
.macro LEA label                         ; current = the address of a label
	.byte	81
	.long	\label - Lvm_base
.endm
.macro LEAB off                          ; current = the address of a B field
	.byte	75
	.short	\off
.endm
.macro LDBE off                          ; current = the big-endian word at current + off
	.byte	76
	.short	\off
.endm
.macro STX n, off                        ; current into the xword or word at local n + off
	.byte	77, \n
	.short	\off
.endm
.macro STW n, off
	.byte	78, \n
	.short	\off
.endm
.macro EQS slot                          ; current = current == a G slot
	.byte	63, (\slot) >> 3
.endm
.macro STE field                         ; current into a B field
	.byte	9
	.short	\field
.endm
.macro LDE field
	.byte	10
	.short	\field
.endm
.macro RC x, top, w, h                ; for 'R': from the content's top-left
	.short	\x, \top, \w, \h
.endm
.macro RN x, y, w, h                  ; for 'N': from the container's bottom-left
	.short	\x, \y, \w, \h
.endm
.macro IMG slot, sym, desc
	CLS	NSImage
	MSG	S_imageWithSystemSymbolName_accessibilityDescription_, "=SS"
	.asciz	"\sym", "\desc"
	STO	\slot
.endm
.macro IMAGE slot, sym, desc
	IMG	\slot, "\sym", "\desc"
	MSG	S_retain, "="
	STO	\slot
.endm
.macro NEWV class, x, top, w, h       ; a new view in the content; it stays current
	CLS	\class
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=R"
	RC	\x, \top, \w, \h
	ADDV
.endm
.macro ADDIN parent                   ; add the current view to a container; it stays current
	STO	G_T3
	LD	\parent
	MSG	S_addSubview_, "O"
	.byte	G_T3 >> 3
	LD	G_T3
.endm
.macro MASKV mask                     ; the current view's autoresizing
	MSG	S_setAutoresizingMask_, "I"
	.byte	\mask
.endm
.macro COLOR slot, r, g, b, a
	CLS	NSColor
	MSG	S_colorWithSRGBRed_green_blue_alpha_, "=KKKK"
	.byte	\r, \g, \b, \a
	MSG	S_retain, "="
	STO	\slot
.endm
.macro LAYERBG color, radius          ; a flat fill with continuous corners for the current view
	MSG	S_setWantsLayer_, "I"
	.byte	1
	STO	G_T3
	LD	\color
	MSG	S_CGColor, "="
	STO	G_T2
	LD	G_T3
	MSG	S_layer, "="
	MSG	S_setBackgroundColor_, "O"
	.byte	G_T2 >> 3
	MSG	S_setCornerRadius_, "D"
	.short	(\radius) * 4
	MSG	S_setCornerCurve_, "S"
	.asciz	"continuous"
	LD	G_T3
.endm
.macro FONT sel, size, weight
	CLS	NSFont
	MSG	\sel, "=DF"
	.short	(\size) * 4
	.byte	\weight
	STO	G_T0
.endm
.macro LABELIN slot, parent, text, x, y, w, h, align, color, mask
	CLS	NSTextField
	MSG	S_labelWithString_, "=S"
	.asciz	"\text"
	STO	\slot
	MSG	S_setFrame_, "N"
	RN	\x, \y, \w, \h
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	\color >> 3
	MSG	S_setAlignment_, "I"
	.byte	\align
	MSG	S_setLineBreakMode_, "I"
	.byte	4                         ; NSLineBreakByTruncatingTail
	MASKV	\mask
	ADDIN	\parent
.endm
.macro SLIDERIN slot, parent, action, x, y, w, max, mask
	CLS	NSSlider
	MSG	S_sliderWithTarget_action_, "=OY"
	.byte	G_CTRL >> 3, (\action - B_ACT) >> 3
	STO	\slot
	MSG	S_setControlSize_, "I"
	.byte	1                         ; small: a slim track
	MSG	S_setFrame_, "N"
	RN	\x, \y, \w, SLIDER_H
	MSG	S_setMaxValue_, "D"
	.short	(\max) * 4
	MSG	S_setTrackFillColor_, "O"
	.byte	G_YEL >> 3
	MASKV	\mask
	ADDIN	\parent
.endm
.macro BTN slot, parent, sym, desc, action, tip, x, y, size, pt, mask, tint
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	(\pt) * 4
	.byte	X_SEMIBOLD
	STO	G_T0
	IMG	G_T1, "\sym", "\desc"
	CLS	NSButton
	MSG	S_buttonWithImage_target_action_, "=OOY"
	.byte	G_T1 >> 3, G_CTRL >> 3, (\action - B_ACT) >> 3
	STO	\slot
	MSG	S_setBordered_, "I"
	.byte	0
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setFrame_, "N"
	RN	\x, \y, \size, \size
	MSG	S_setToolTip_, "S"
	.asciz	"\tip"
	MSG	S_setContentTintColor_, "O"
	.byte	\tint >> 3
	MASKV	\mask
	ADDIN	\parent
.endm
.macro SUBMENU title
	CLS	NSMenu
	MSG	S_alloc, "="
	MSG	S_initWithTitle_, "=S"
	.asciz	"\title"
	STO	G_T1
	LD	G_T0
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SIS"
	.asciz	"\title"
	.byte	0
	.asciz	""
	MSG	S_setSubmenu_, "O"
	.byte	G_T1 >> 3
.endm
.macro ITEM title, action, key
	.byte	8
	.asciz	"\title"
	.byte	(\action - B_ACT) >> 3
	.asciz	"\key"
.endm
.macro NESTED title                   ; a submenu in the current menu (G_T1); it becomes current, in G_T2
	CLS	NSMenu
	MSG	S_alloc, "="
	MSG	S_initWithTitle_, "=S"
	.asciz	"\title"
	STO	G_T2
	LD	G_T1
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SIS"
	.asciz	"\title"
	.byte	0
	.asciz	""
	MSG	S_setSubmenu_, "O"
	.byte	G_T2 >> 3
	LD	G_T2
.endm
.macro SPEED title, percent           ; an item of the Speed submenu (G_T2); it stays current
	LD	G_T2
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SYS"
	.asciz	"\title"
	.byte	(S_act_speed_ - B_ACT) >> 3
	.asciz	""
	MSG	S_setTag_, "I"
	.byte	\percent
.endm
.macro MASK flags                     ; the last item's modifiers, when not Command alone
	MSG	S_setKeyEquivalentModifierMask_, "X"
	.long	\flags
.endm
.macro SEP
	CLS	NSMenuItem
	MSG	S_separatorItem, "="
	STO	G_SEP
	LD	G_T1
	MSG	S_addItem_, "O"
	.byte	G_SEP >> 3
.endm
.macro METHOD sel, imp, types=""         ; - (void)action:(id)sender, unless types say otherwise
	.byte	7, (\sel - B_ACT) >> 3
	.long	\imp - Lvm_base
	.asciz	"\types"
.endm

; ---- Constants ----

; GCD.
.equ QOS_CLASS_USER_INITIATED,   0x19
.equ DISPATCH_TIME_FOREVER,      -1

; Network timeouts and limits.
.equ API_TIMEOUT_MS,             30000
.equ BUF_MAX,                    0x800000 ; 8 MiB cap for any buffered body
.equ CHUNK,                      0xa00000 ; 10 MiB: larger upstream ranges are throttled to realtime
.equ HIDE_TICKS,                 3        ; idle seconds before the controls leave a playing video
.equ VIDEO_MAX_H,                2160     ; the tallest video stream picked
.equ SKIP_SECONDS,               10
.equ VOLUME_STEP,                5

; The engine: This Mac's own player.
.equ QOS_CLASS_USER_INTERACTIVE, 0x21
.equ PROT_READ,                  1
.equ MAP_PRIVATE,                2
.equ MADV_SEQUENTIAL,            2
.equ STAT_SIZE,                  96       ; struct stat: st_size
.equ kAudioFormatFlagIsFloat,    1
.equ kAudioFormatFlagIsBigEndian, 2
.equ kAudioFormatFlagIsSignedInteger, 4
.equ kAudioFormatFlagIsPacked,   8
.equ RENDER_FAILED,              2        ; AVQueuedSampleBufferRenderingStatusFailed
.equ WAIT_TRIES,                 2000     ; 5 ms polls for the first picture before the clock starts anyway
.equ WAIT_NS,                    5000000
.equ LEAD_MS,                    350      ; a picture queued at most this far ahead (net_tick asks again every eighth of a second; 2x speed still has a tick to spare)
.equ AUDIO_PREROLL,              2        ; packets decoded before a seek target, so the decoder has its overlap
.equ ABATCH,                     7        ; at most 2^7 sound samples in a row per buffer: each buffer costs the renderer ~130k instructions
.equ TRACKS,                     8
.equ RQS,                        16       ; requests at once
.equ STREAMS,                    3        ; network streams: picture, sound, subtitles
.equ FIFO_N,                     4096     ; samples a track's queue holds
.equ AHEAD_V,                    480      ; queued pictures and sound packets before a stream stops fetching
.equ AHEAD_A,                    768
.equ AHEAD_S,                    64       ; and cues
.equ ARENA_MAX,                  0x800000 ; 8 MiB of media data per arena
.equ BOX_MAX,                    0x1000000 ; the largest box collected (moov, moof, sidx)
.equ RETRY_NS,                   1000000000
.equ NET_TRIES,                  3
.equ TICK_NS,                    125000000 ; the network check: a stall holds the clock until STALL_FULL ms are in
.equ STALL_LOW,                  250
.equ STALL_FULL,                 2000
.equ BPS_START,                  4000000  ; HLS starts with the best variant under this, then follows the measured speed
.equ HLS_LIVE_BACK,              3        ; a broadcast starts this many segments from its live edge
.equ HLS_T0_BITS,                4
.equ CLOCK_UPTIME_RAW,           8
.equ AFS_READY,                  0x72656479 ; 'redy'
.equ AFS_FORMAT,                 0x64666d74 ; 'dfmt'
.equ AFS_COOKIE,                 0x6d676963 ; 'mgic'
.equ AFS_DOFF,                   0x646f6666 ; 'doff': where the sound data starts
.equ AFS_PCNT,                   0x70636e74 ; 'pcnt': its packets
.equ AFS_BRAT,                   0x62726174 ; 'brat': its bit rate
.equ AFS_PNFO,                   0x706e666f ; 'pnfo': its priming and remainder frames
; seg_scan's result: a media playlist's segment.
.equ SG_URI,                     0        ; its URI line, and the line's end
.equ SG_URIE,                    8
.equ SG_T,                       16       ; start and duration, ms
.equ SG_DUR,                     24
.equ SG_BRL,                     32       ; byte range: length (0: all) and offset
.equ SG_BRO,                     40
.equ SG_KEY,                     48       ; its EXT-X-KEY line, or 0
.equ SG_MAP,                     56       ; its EXT-X-MAP line, or 0
.equ SG_SEQ,                     64       ; its media sequence number
.equ SG_SEQ0,                    72       ; the playlist's first
.equ SG_TDUR,                    80       ; w: target duration, ms
.equ SG_END,                     84       ; w: EXT-X-ENDLIST
.equ SG_DSEQ,                    88
.equ SG_N,                       92       ; w: segments counted
.equ SG_SIZE,                    96

; Request record: what becomes of a task's bytes and of its end.
.equ RQ_SINK,                    0        ; sink(record, bytes, length)
.equ RQ_DONE,                    8        ; done(record, ok, task)
.equ RQ_REQ,                     16       ; the NSURLRequest to start
.equ RQ_TASK,                    24       ; its task, while it runs
.equ RQ_BUF,                     32       ; {data, len}: fetch's body
.equ RQ_SEM,                     48       ; signaled when fetch's request ends
.equ RQ_OK,                      56       ; w
.equ RQ_SIZE,                    64

; A YouTube play for the engine: generation, live, length in ms, picture and sound URLs (owned).
.equ YT_GEN,                     0
.equ YT_LIVE,                    4
.equ YT_DUR,                     8
.equ YT_V,                       16
.equ YT_A,                       24

; Track: one stream of an open file, its sample tables read in place, and a cursor over them.
.equ TR_KIND,                    0        ; w: 'v' picture, 'a' sound, 0 none
.equ TR_TS,                      4        ; w: timescale
.equ TR_FD,                      8        ; CMFormatDescription
.equ TR_SHIFT,                   16       ; the edit list's start, in timescale units
.equ TR_TGT,                     24       ; earlier samples are decoded, not shown or heard
.equ TR_N,                       32       ; w: samples
.equ TR_FIXED,                   36       ; w: every sample's size, or 0
.equ TR_STSD,                    40       ; the first sample description
.equ TR_STTS,                    48       ; table payloads (version and flags first), 0 if absent
.equ TR_CTTS,                    56
.equ TR_STSC,                    64
.equ TR_STSZ,                    72
.equ TR_STCO,                    80
.equ TR_CO64,                    88
.equ TR_STSS,                    96
.equ TR_NST,                     104      ; w: their entries
.equ TR_NCT,                     108
.equ TR_NSC,                     112
.equ TR_NCH,                     116
.equ TR_NSS,                     120
.equ TR_STSDN,                   124      ; w: the description's length
.equ TR_I,                       128      ; the cursor (64 bytes): w sample
.equ TR_STI,                     132      ; w: stts entry, and samples left in it
.equ TR_STL,                     136
.equ TR_CTI,                     140      ; w: ctts entry, and samples left in it
.equ TR_CTL,                     144
.equ TR_SCI,                     148      ; w: stsc entry
.equ TR_CH,                      152      ; w: chunk, and samples left in it
.equ TR_CHL,                     156
.equ TR_SSI,                     160      ; w: the first stss entry at or past the sample
.equ TR_DTS,                     168
.equ TR_OFF,                     176      ; the sample's file offset
.equ TR_FH,                      192      ; w: its queue's head and tail
.equ TR_FT,                      196
.equ TR_FN,                      200      ; w: fragment samples listed, and the next one
.equ TR_FI,                      204
.equ TR_DDUR,                    208      ; w: trex defaults: duration, size, flags
.equ TR_DSIZE,                   212
.equ TR_DFLAGS,                  216
.equ TR_FCAP,                    220      ; w: the list's room
.equ TR_SRC,                     224      ; w: 0 the mapped file, 1 a stream's queue
.equ TR_ID,                      228      ; w: track_ID
.equ TR_STARVE,                  232      ; w: the renderer stopped asking on an empty queue
.equ TR_LANG,                    236      ; w: its language's three letters ("eng"), 0 if none
.equ TR_FQ,                      240      ; the queue: CMSampleBufferRef[FIFO_N]
.equ TR_FL,                      248      ; the fragment's samples: {offset, size, duration, composition, flags}[]
.equ TR_ST,                      256      ; the stream that feeds it
.equ TR_FDTS,                    264      ; the next fragment sample's decode time
.equ TR_LAST,                    272      ; the last sample made's presentation time
.equ TR_AFS,                     280      ; its AudioFileStream, which finds the packets of a sound stream
.equ TR_APTS,                    288      ; the next packet's presentation time
.equ TR_ASR,                     296      ; w: sample rate and frames per packet
.equ TR_AFPP,                    300
.equ TR_ROT,                     304      ; w: the picture's turn from its matrix, degrees counterclockwise (0, 90, 180, -90)
.equ TR_DW,                      308      ; w: its shown size, pixel aspect and clean aperture applied
.equ TR_DH,                      312
.equ TR_SNAP,                    320      ; a saved cursor
.equ TR_PRIM,                    384      ; w: a sound file's encoder priming, frames (cut from its timeline)
.equ TR_CUR,                     388      ; w: the cursor reads 0 MP4's tables, 1 Matroska's blocks, 2 FLV's tags
.equ TR_MNUM,                    392      ; w: Matroska: its track number; FLV: its tag type
.equ TR_MFPP,                    396      ; w: sound: frames per packet, 0 from the timestamps, -1 Opus's own, -2 PCM (a block's every frame)
.equ TR_MSEG,                    400      ; Matroska: where the segment's data starts, which its index counts from
.equ TR_MCL,                     408      ; where the first cluster (FLV: the first tag) is
.equ TR_MCUES,                   416      ; the index (Matroska: the Cues' data and end; FLV: the keyframes' positions and times), in memory
.equ TR_MCUEN,                   424
.equ TR_MFAC,                    432      ; d: track units per tick
.equ TR_MPREN,                   448      ; w: header stripping: how many bytes are cut from every frame (TR_MPREB)
.equ TR_MDDUR,                   452      ; w: a frame's default duration
.equ TR_MDEF,                    456      ; w: a default track
.equ TR_MTOL,                    460      ; w: the timestamps' rounding: a sound packet within it of the last one's end follows it
.equ TR_MEST,                    464      ; w: TR_MDDUR is the smallest step between a picture's frames seen so far (the file gives none)
.equ TR_MWAIT,                   468      ; w: a stream's cursor waits for bytes: it reads on from TR_XEND when they come
.equ TR_AREM,                    472
.equ TR_MPREB,                   480      ; header stripping's bytes (at most 16)
.equ TR_XDTS,                    496      ; Matroska: the last picture's decode time, made up (1 << 63: none since the seek)
.equ TR_XKEY,                    504      ; where reading starts for the cursor's frame: its tag, its cluster
.equ TR_XSIZE,                   TR_STI   ; Matroska's and FLV's cursor, in TR_I's 64 bytes: the frame's size in the file, w
.equ TR_XDUR,                    TR_STL   ; w: its duration
.equ TR_XCTS,                    TR_CTI   ; w: its composition offset
.equ TR_XSYNC,                   TR_CTL   ; bit 0 sync, bits 1-2 its block's lacing, 8-15 frames after it there, 16-63 where its cluster ends (all ones: outside one)
.equ TR_XLP,                     TR_CH    ; where the next one's size is given (a file offset)
.equ TR_XEND,                    TR_SSI   ; where its block (FLV: its tag) ends, and the cursor reads on
.equ TR_XCTC,                    TR_OFF + 8 ; its cluster's time, ticks
.equ TR_SIZE,                    512

; Stream: one URL's bytes from the network, parsed as they come.
.equ ST_URL,                     0        ; char*, owned
.equ ST_LEN,                     8        ; its size, 0 if unknown
.equ ST_POS,                     16       ; the next byte to ask for
.equ ST_SPOS,                    24       ; the next byte to parse
.equ ST_LEFT,                    32       ; bytes left in the box or media data
.equ ST_BOXPOS,                  40       ; where the box started
.equ ST_BBUF,                    48       ; a small box being collected, and its bytes so far
.equ ST_BN,                      56
.equ ST_MOOV,                    64       ; the movie box, kept: a whole file's cursors read its tables
.equ ST_SIDX,                    72       ; the segment index, kept for seeks, and where it ended
.equ ST_SIDXEND,                 80
.equ ST_AR,                      88       ; the arena: media data as it arrives
.equ ST_ARBB,                    96       ; its CMBlockBuffer, which frees it after the last sample
.equ ST_ARPOS,                   104      ; the stream position of its first byte
.equ ST_ARN,                     112
.equ ST_ARCAP,                   120
.equ ST_MDEND,                   128      ; where the media data ends
.equ ST_TR,                      136      ; the tracks it feeds (2)
.equ ST_PLOFF,                   152
.equ ST_PEND,                    160      ; a seek waiting for the index, ms, or -1
.equ ST_GOT,                     168      ; bytes the running request gave
.equ ST_PST,                     176      ; w: 0 box header, 1 box to collect, 2 media data, 3 to skip
.equ ST_HN,                      180      ; w: header bytes so far
.equ ST_HB,                      184      ; the header (16 bytes)
.equ ST_BOXT,                    200      ; w: the box's type
.equ ST_FETCH,                   204      ; w: a request runs
.equ ST_EOS,                     208      ; w: no more bytes
.equ ST_ERRS,                    212      ; w: failures in a row
.equ ST_FRAG,                    220      ; w: fragmented: samples come from moof boxes
.equ ST_RETRY,                   224      ; w: a retry is scheduled
.equ ST_ANS,                     228      ; w: the running request's answer was checked
.equ ST_SKIP,                    232      ; bytes of it still to drop: a server without ranges sends from byte 0
.equ ST_RQ,                      240      ; its request record
.equ ST_KIND,                    304      ; w: 0 one URL's bytes, 1 an HLS media playlist's segments
.equ ST_REQT,                    308      ; w: what the request fetches: 0 stream bytes, 1 a playlist, 2 a key, 3 a segment, 4 an init segment
.equ ST_TXT,                     312      ; text being collected (a playlist, a key, an encrypted segment), and its length
.equ ST_TXTN,                    320
.equ ST_PLURL,                   328      ; char*: the media playlist's URL
.equ ST_PL,                      336      ; char*: its text
.equ ST_SEQ,                     344      ; the next segment's media sequence number
.equ ST_SEGN,                    352
.equ ST_SEGT,                    360      ; its start, ms
.equ ST_MAPURL,                  368      ; char*: the init segment read
.equ ST_T1,                      376      ; when the segment's request started, ns
.equ ST_SEGF,                    384      ; w: the segment's format: 0 unknown, 1 TS, 2 boxes, 3 packed audio
.equ ST_ENC,                     388      ; w: it is AES-128 encrypted
.equ ST_TDUR,                    392      ; w: target duration, ms
.equ ST_ENDED,                   396      ; w: the playlist is complete (on demand)
.equ ST_PMT,                     400      ; w: TS: the program map's PID, the picture's, the sound's
.equ ST_VPID,                    404
.equ ST_APID,                    408
.equ ST_VHEVC,                   412      ; w: the picture is HEVC
.equ ST_TSN,                     416      ; w: bytes of a partial TS packet
.equ ST_PSNEW,                   420      ; w: parameter sets changed: a new format before the next picture
.equ ST_STALE,                   424      ; w: its playlist is due again, until a new one comes
.equ ST_KEY,                     432      ; AES key and IV, 16 bytes each
.equ ST_IV,                      448
.equ ST_VT,                      464      ; the TS picture and sound tracks
.equ ST_AT,                      472
.equ ST_VPES,                    480      ; the PES being gathered, picture and sound: {data, len, cap}
.equ ST_APES,                    504
.equ ST_TSC,                     528      ; a partial TS packet (188)
.equ ST_PS,                      720      ; parameter sets: VPS, SPS, PPS, each {w length, bytes[252]}
.equ ST_RQURL,                   ST_PS + 3 * 256 ; char*: the URL a request of the stream's own runs for
.equ ST_VPEN,                    ST_RQURL + 8 ; the picture's access unit waiting for the next PES, which may end it: {data, len, room, pts, dts, the last duration}
.equ ST_XHEAD,                   ST_VPEN + 48 ; w: Matroska, FLV: their tracks are made
.equ ST_XMODE,                   ST_XHEAD + 4 ; w: the bytes are the Cues, collected for a seek
.equ ST_XCUEP,                   ST_XHEAD + 8 ; where the Cues are, fetched for the first seek (0: read, or none)
.equ ST_XIDX,                    ST_XCUEP + 8 ; the index its tracks read (the Cues, FLV's onMetaData), owned, and its length
.equ ST_XIDXN,                   ST_XIDX + 8
.equ ST_XKEYS,                   ST_XIDXN + 8 ; Matroska, FLV: the pictures' key frames read so far, {where reading starts for one, its time in ms}, in file order (XKEYS_N at most), owned, and their count
.equ ST_XKEYN,                   ST_XKEYS + 8
.equ ST_XLEN,                    ST_XKEYN + 8 ; the stream's length from a range's answer
.equ ST_HUNGRY,                  ST_XLEN + 8
.equ ST_PAUSEAT,                 ST_HUNGRY + 8
.equ ST_SEGOFF,                  ST_PAUSEAT + 8
.equ ST_KEYURL,                  ST_SEGOFF + 8 ; char*: the key in ST_KEY
.equ ST_T0,                      ST_KEYURL + 8
.equ ST_SIZE,                    ST_T0 + 8

; Track: title, artist and artwork URL.
.equ T_TITLE,                    0        ; char[512]
.equ T_ARTIST,                   512      ; char[256]
.equ T_ART,                      768      ; char[2048]
.equ T_SIZE,                     2816

; Fmt: what HLS needs of a YouTube stream.
.equ FMT_INIT,                   0        ; last byte of the init segment
.equ FMT_IDX0,                   8        ; first and last byte of the segment index (sidx)
.equ FMT_IDX1,                   16
.equ FMT_RATE,                   24       ; bits per second
.equ FMT_CODECS,                 32       ; char[64], e.g. "avc1.640028"
.equ FMT_SIZE,                   96

; Play job: main -> worker -> main.
.equ JOB_QUERY,                  0        ; char*, a link, search text or file path (owned)
.equ JOB_RESULT,                 8        ; int, PLAY_*
.equ JOB_LIVE,                   12       ; int
.equ JOB_DUR,                    16       ; seconds, 0 when live or unknown
.equ JOB_ERR,                    24       ; char*, why it failed, or NULL
.equ JOB_KIND,                   32       ; int, KIND_*
.equ JOB_GEN,                    36       ; int, G_PLAYGEN when asked
.equ JOB_TRACK,                  48       ; Track
.equ JOB_AFMT,                   JOB_TRACK + T_SIZE ; Fmt of the sound stream
.equ JOB_VFMT,                   JOB_AFMT + FMT_SIZE ; and of the picture stream
.equ JOB_MSG,                    JOB_VFMT + FMT_SIZE ; char[128], an error message
.equ JOB_URL,                    JOB_MSG + 128      ; char[4096], the media URL
.equ JOB_VURL,                   JOB_URL + 4096     ; char[4096], the video stream's URL, or ""
.equ JOB_HLS,                    JOB_VURL + 4096    ; char[4096], YouTube's own HLS, or ""
.equ JOB_SIZE,                   JOB_HLS + 4096
.equ KIND_YOUTUBE,               0        ; a YouTube link or search
.equ KIND_WEB,                   1        ; any other web address, played as it is
.equ KIND_FILE,                  2        ; a file on this Mac (JOB_QUERY is its path)
.equ PLAY_OK,                    0
.equ PLAY_FAILED,                1

; AppKit.
.equ WIN_STYLE,                  0x800f   ; titled|closable|miniaturizable|resizable|fullSizeContentView
.equ NSEventTypeLeftMouseDown,   1
.equ NSEventTypeLeftMouseDragged, 6
.equ FULL_SCREEN_PRIMARY,        128
.equ TRACK_OPTIONS,              0x282    ; mouse moved, always active, in the visible rect
.equ PLAYER_ITEM_FAILED,         2

; Autoresizing: which margins or sizes follow the window.
.equ AR_LEFT,                    1
.equ AR_WIDTH,                   2
.equ AR_RIGHT,                   4
.equ AR_BOTTOM,                  8
.equ AR_HEIGHT,                  16
.equ AR_TOP,                     32

; Window layout in points: views are built for the smallest window (from the content's top-left; inside a container, from its bottom-left), then follow it.
.equ WIN_W,                      640
.equ WIN_H,                      400
.equ START_W,                    880
.equ START_H,                    560
.equ BAR_M,                      12       ; the control bar floats this far from the edges
.equ BAR_W,                      WIN_W - 2 * BAR_M
.equ BAR_H,                      96
.equ STAGE_B,                    BAR_M + BAR_H + 16 ; artwork and link field sit between the bar
.equ STAGE_T,                    40       ; and the title bar
.equ ART_RADIUS,                 14
.equ ART_MAX,                    720
.equ SPIN_S,                     32
.equ URL_W,                      520
.equ URL_H,                      48
.equ STATUS_T,                   36
.equ LABEL_H,                    16
.equ SLIDER_H,                   20
.equ TIME_W,                     60
.equ ROW1_Y,                     BAR_H - 12 - SLIDER_H ; position slider
.equ ROW2_C,                     34       ; middle of the second row
.equ PLAY_S,                     44
.equ BTN_S,                      32
.equ ICON_S,                     24
.equ BTN_GAP,                    14
.equ PLAY_X,                     BAR_W / 2 - PLAY_S / 2
.equ BACK_X,                     PLAY_X - BTN_GAP - BTN_S
.equ FWD_X,                      PLAY_X + PLAY_S + BTN_GAP
.equ AIR_W,                      28
.equ AIR_X,                      BAR_W - 16 - AIR_W
.equ VOL_W,                      64
.equ VOL_X,                      AIR_X - 8 - VOL_W
.equ MUTE_X,                     VOL_X - 4 - ICON_S
.equ AO_X,                       MUTE_X - 12 - ICON_S
.equ TEXT_W,                     BACK_X - 32

; UI timing, in timer ticks (one per second).
.equ STATUS_TICKS,               6
.equ HOLD_TICKS,                 2

; G: scalars at fixed offsets from x28; string literals follow them.
.equ G_APP,                      0
.equ G_CTRL,                     8
.equ G_PLAYER,                   32       ; AVPlayer
.equ G_LOCK,                     48       ; os_unfair_lock
.equ G_PLAYGEN,                  84       ; the newest play (written on main)
.equ G_LTDUR,                    96       ; This Mac's duration (main)
.equ G_TICK,                     104      ; timer ticks since launch
.equ G_SEEKH,                    112      ; tick until which polled positions are ignored
.equ G_VOLH,                     120      ; tick until which polled volumes are ignored
.equ G_MSGT,                     128      ; tick after which the status message expires
.equ G_ARTGEN,                   136      ; artwork request generation
.equ G_LOADING,                  156      ; a link is being resolved
.equ G_PPSHOWN,                  160      ; play/pause shows "pause"
.equ G_MUTESHOWN,                164
.equ G_SEEKDRAG,                 168
.equ G_VOLDRAG,                  172
.equ G_MSGERR,                   176      ; the status message is an error
.equ G_AONLY,                    180      ; Audio Only: no picture is fetched or shown
.equ G_WIN,                      184      ; views and images (main thread)
.equ G_CONTENT,                  192
.equ G_FIELD,                    200      ; the link field of Open from URL
.equ G_SPIN,                     208
.equ G_ART,                      216
.equ G_TITLE,                    224
.equ G_ARTIST,                   232
.equ G_CUR,                      240
.equ G_DUR,                      248
.equ G_BACK,                     256      ; enabled when seekable: back, forward, position
.equ G_FWD,                      264
.equ G_POS,                      272
.equ G_PP,                       280
.equ G_MUTE,                     288
.equ G_VOL,                      296
.equ G_VIDEO,                    304      ; the view of This Mac's picture
.equ G_STATUS,                   312
.equ G_IMGPLAY,                  328
.equ G_IMGPAUSE,                 336
.equ G_IMGMUTED,                 344
.equ G_IMGUNMUTED,               352
.equ G_SECOND,                   360      ; colors (main)
.equ G_TEXT,                     G_SECOND + 8
.equ G_YEL,                      G_TEXT + 8
.equ G_RED,                      G_YEL + 8
.equ G_BGC,                      G_RED + 8
.equ G_SURF,                     G_BGC + 8
.equ G_SURF2,                    G_SURF + 8
.equ G_T0,                       G_SURF2 + 8 ; scratch objects of the UI programs
.equ G_T1,                       G_T0 + 8
.equ G_T2,                       G_T1 + 8
.equ G_T3,                       G_T2 + 8
.equ G_WORKQ,                    G_T3 + 8 ; the global user-initiated queue
.equ G_BAR,                      G_WORKQ + 8 ; the control bar
.equ G_URLBOX,                   G_BAR + 8 ; Open from URL's floating field
.equ G_AOBTN,                    G_URLBOX + 8 ; the Audio Only button and menu item
.equ G_AOITEM,                   G_AOBTN + 8
.equ G_ARTASP,                   G_AOITEM + 8 ; the artwork's height / width (double)
.equ G_IDLE,                     G_ARTASP + 8 ; ticks since the mouse last moved
.equ G_HASVIDEO,                 G_IDLE + 4 ; This Mac's media has a picture
.equ G_BARHID,                   G_HASVIDEO + 4 ; the bar is faded out
.equ G_HOVER,                    G_BARHID + 4 ; the mouse is over the bar
.equ G_ARTOK,                    G_HOVER + 4 ; the artwork has an image
.equ G_FAILED,                   G_ARTOK + 4 ; This Mac's item failed and it was reported
.equ G_AV1,                      G_FAILED + 4 ; AV1 decodes in hardware
.equ G_NOTE,                     G_AV1 + 8 ; the artwork card's music note, shown without an image
.equ G_RATE,                     G_NOTE + 8 ; Playback > Speed (float)
.equ G_SUBMENU,                  G_RATE + 8 ; View > Subtitles
.equ G_PIP,                      G_SUBMENU + 8 ; the Picture in Picture controller, made on first use
.equ G_MEDIAQ,                   G_PIP + 8 ; the engine's serial queue
.equ G_SBV,                      G_MEDIAQ + 8 ; the view of the engine's picture
.equ G_SBLAYER,                  G_SBV + 8 ; and its layer, made on the media queue
.equ G_MODE,                     G_SBLAYER + 8 ; 0: the engine plays, 1: AVPlayer (main)
.equ G_PLAYING,                  G_MODE + 4 ; the engine should be playing (main)
.equ G_VOLPCT,                   G_PLAYING + 4 ; volume 0..100 and mute, for both players (main)
.equ G_MUTED,                    G_VOLPCT + 4
.equ G_SEEKPEND,                 G_MUTED + 4 ; a seek is queued for the engine
.equ G_SEEKTO,                   G_SEEKPEND + 8 ; its target, ms
.equ G_CLOCKQ,                   G_SEEKTO + 8 ; a serial queue for the clock's slow stops
.equ G_SHOWPOS,                  G_CLOCKQ + 8 ; the position show_time was given, drawn or not (main)
.equ G_SIZE,                     G_SHOWPOS + 8

; ---- Data ----

	.section __DATA,__data
	.p2align 3

; B: the large buffers, at fixed offsets from x27.
.equ B_UIMSG,                    0        ; char[256], status message (main)
.equ B_UIARTIST,                 B_UIMSG + 256 ; char[256], last rendered artist (main)
.equ B_UIART,                    B_UIARTIST + 256 ; char[2048], artwork shown or loading (main)
.equ B_UITITLE,                  B_UIART + 2048 ; char[512], last rendered title (main)
.equ B_LTTRACK,                  B_UITITLE + 512 ; This Mac's track (main)
.equ B_REG,                      (B_LTTRACK + T_SIZE + 4095) & ~4095 ; the registry, 4 KiB-aligned: one add reaches it


; SYM / OBJC name, pieces — an imported symbol / class in the registry, its name whole or in pieces that spell it (FN, defined with each pass, is a function called by name).
.macro SYM name, a, b, c, d, e, f, g, h, i, j, k, l, m
	SPELL	F_\name, \name, \a, \b, \c, \d, \e, \f, \g, \h, \i, \j, \k, \l, \m
.endm
.macro OBJC name, a, b, c, d, e, f, g, h, i, j, k, l, m ; found with objc_getClass
	SPELL	C_\name, \name, \a, \b, \c, \d, \e, \f, \g, \h, \i, \j, \k, \l, \m
.endm
.macro SPELL sym, name, a, b, c, d, e, f, g, h, i, j, k, l, m
	.ifb	\a
	REG	\sym, \name
	.else
	.ifnc	\name, \a\b\c\d\e\f\g\h\i\j\k\l\m
	.error	"the pieces do not spell the name"
	.endif
	REG	\sym, \a, \b, \c, \d, \e, \f, \g, \h, \i, \j, \k, \l, \m
	.endif
.endm

; REGISTRY — imported symbols, classes, then selectors, looked up by name once at launch into B.
.macro REGISTRY
	SYM	CFArrayGetValueAtIndex, CF,Array,Get,Value,At,In,dex
	SYM	CFDictionarySetValue, CFDi,ction,ary,Set,Value
	SYM	CFNotificationCenterAddObserver, CF,Notific,ation,Cen,ter,Add,Observ,er
	SYM	CFNotificationCenterGetLocalCenter, CF,Notific,ation,Cen,ter,Get,Lo,cal,Cen,ter
	FN	CFRelease, CFR,elease
	SYM	CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData, CM,Audio,FormatDescriptionCreateFrom,BigEndianS,ound,Description,Data
	SYM	CMBlockBufferCreateWithBufferReference, CM,Block,Buffer,Create,With,Buffer,Reference
	FN	CMBlockBufferCreateWithMemoryBlock, CM,Block,Buffer,Create,With,Memory,Block
	SYM	CMSampleBufferCreateReady, CM,SampleBuffer,Create,Ready
	SYM	CMSampleBufferGetSampleAttachmentsArray, CM,SampleBuffer,Get,Sa,mple,Attachment,s,Array
	SYM	CMSetAttachment, CM,Set,Attachment
	SYM	CMTimeCopyAsDictionary, CM,Time,CopyAsDi,ction,ary
	SYM	CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData, CMVideo,FormatDescriptionCreateFrom,BigEndian,Image,Description,Data
	FN	CMVideoFormatDescriptionCreateFromH264ParameterSets, CMVideo,FormatDescriptionCreateFrom,H264Par,ame,ter,Set,s
	FN	CMVideoFormatDescriptionCreateFromHEVCParameterSets, CMVideo,FormatDescriptionCreateFrom,HEVCPar,ame,ter,Set,s
	SYM	CMAudioFormatDescriptionCreate, CM,Audio,FormatDescription,Create
	SYM	CMAudioSampleBufferCreateReadyWithPacketDescriptions, CM,Audio,SampleBuffer,Create,Ready,With,P,ack,et,Description,s
	FN	CMBlockBufferGetDataPointer, CM,Block,Buffer,Get,Data,Po,in,ter
	FN	CMFormatDescriptionCreate, CM,FormatDescription,Create
	FN	CMFormatDescriptionGetMediaSubType, CM,FormatDescription,Get,Media,Sub,Type
	FN	CMSampleBufferGetDataBuffer, CM,SampleBuffer,Get,Data,Buffer
	SYM	CMSampleBufferGetDuration, CM,SampleBuffer,Get,Dur,ation
	SYM	CMSampleBufferGetFormatDescription, CM,SampleBuffer,Get,FormatDescription
	SYM	CMSampleBufferGetPresentationTimeStamp, CM,SampleBuffer,Get,P,res,ent,ation,Time,Stamp
	SYM	CMVideoFormatDescriptionGetPresentationDimensions, CMVideo,FormatDescription,Get,P,res,ent,ation,D,ime,n,sion,s
	SYM	AudioFileStreamClose, AudioFileStream,Close
	FN	AudioFileStreamGetProperty, AudioFileStream,Get,Pro,per,ty
	SYM	AudioFileStreamGetPropertyInfo, AudioFileStream,Get,Pro,per,ty,In,fo
	SYM	AudioFileStreamOpen, AudioFileStream,Open
	FN	AudioFileStreamParseBytes, AudioFileStream,ParseBy,tes
	SYM	AudioFileStreamSeek, AudioFileStream,Seek
	SYM	VTDecompressionSessionCreate, VTDecompression,Session,Create
	SYM	VTDecompressionSessionInvalidate, VTDecompression,Session,In,val,id,ate
	SYM	CCCrypt
	SYM	arc4random_uniform, arc4random_uni,for,m
	FN	asprintf, aspr,in,tf
	FN	bzero
	SYM	calloc, cal,loc
	FN	clock_gettime_nsec_np, c,loc,k_gett,ime,_nsec_np
	FN	close
	FN	dispatch_after_f, dispatch_,af,ter,_f
	FN	dispatch_async_f, dispatch_,async_f
	SYM	dispatch_semaphore_create, dispatch_,semaphore_,cre,ate
	SYM	dispatch_semaphore_signal, dispatch_,semaphore_,signal
	SYM	dispatch_semaphore_wait, dispatch_,semaphore_,wait
	SYM	dispatch_sync_f, dispatch_,sync_f
	FN	dispatch_time, dispatch_,t,ime
	FN	free
	SYM	fstat
	SYM	madvise, madv,is,e
	FN	malloc, mal,loc
	FN	memcmp
	FN	memcpy
	SYM	memmove
	SYM	mmap
	FN	munmap
	FN	objc_autoreleasePoolPop, objc_,au,tor,elease,PoolPop
	FN	objc_autoreleasePoolPush, objc_,au,tor,elease,PoolPush
	SYM	objc_getClass, objc_,getC,lass
	FN	objc_msgSend, objc_,msgSend
	SYM	open
	SYM	os_unfair_lock_lock, os_unfair_lock_,loc,k
	SYM	os_unfair_lock_unlock, os_unfair_lock_,un,loc,k
	FN	realloc, rea,l,loc
	FN	sel_registerName, sel_,register,N,ame
	FN	snprintf, snpr,in,tf
	SYM	strcasestr, str,case,str
	FN	strchr, str,chr
	FN	strcmp, str,cmp
	FN	strcspn, str,cspn
	FN	strdup, str,dup
	FN	strlcpy, str,lcpy
	FN	strlen, str,len
	FN	strncmp, str,ncmp
	FN	strnstr, str,n,str
	FN	strstr, str,str
	SYM	strtod, str,tod
	FN	strtol, str,tol
	SYM	NSFontWeightMedium, NSFontWeight,Medium
	SYM	NSFontWeightRegular, NSFontWeight,Regular
	SYM	NSFontWeightSemibold, NSFontWeight,Semibold
	SYM	VTIsHardwareDecodeSupported, VTIsHardwareDec,ode,Supported
	SYM	VTRegisterSupplementalVideoDecoderIfAvailable, VT,Reg,is,ter,Supplem,ent,al,Video,Dec,ode,r,IfAvail,able
	SYM	_NSConcreteGlobalBlock, _,NS,ConcreteGlobal,Block
	SYM	_dispatch_main_q, _,dispatch_,ma,in,_q
	SYM	class_addMethod, c,lass,_,add,Method
	SYM	dispatch_get_global_queue, dispatch_,get_global_q,ueue
	SYM	dispatch_queue_attr_make_with_autorelease_frequency, dispatch_,queue_attr_make_with_,au,tor,elease,_frequency
	SYM	dispatch_queue_attr_make_with_qos_class, dispatch_,queue_attr_make_with_,qos_c,lass
	SYM	dispatch_queue_create, dispatch_,q,ueue,_cre,ate
	SYM	kCFBooleanTrue
	SYM	kCMImageDescriptionFlavor_ISOFamily, k,CM,Image,Description,Flavor_ISOFamily
	SYM	kCMSampleAttachmentKey_DoNotDisplay, kCMSampleAttachmentKey_,DoNot,Display
	SYM	kCMSampleAttachmentKey_NotSync, kCMSampleAttachmentKey_,NotSync
	SYM	kCMSampleBufferAttachmentKey_TrimDurationAtStart, k,CM,SampleBuffer,Attachment,Key_TrimDur,ation,AtStart
	SYM	kCMSoundDescriptionFlavor_ISOFamily, k,CM,S,ound,Description,Flavor_ISOFamily
	SYM	objc_allocateClassPair, objc_,al,loc,ate,C,lass,Pair
	SYM	objc_registerClassPair, objc_,register,C,lass,Pair
	REGCLS
	OBJC	AVPlayer, AV,Player
	OBJC	AVPlayerItem, AV,Player,Item
	OBJC	AVPictureInPictureController, AV,Picture,InPictureController
	OBJC	AVPictureInPictureControllerContentSource, AV,Picture,InPictureController,Content,Source
	OBJC	AVPlayerLayer, AV,Player,Layer
	OBJC	AVRoutePickerView, AV,RoutePicker,View
	OBJC	AVSampleBufferAudioRenderer, AV,SampleBuffer,Audio,Render,er
	OBJC	AVSampleBufferDisplayLayer, AV,SampleBuffer,Display,Layer
	OBJC	AVSampleBufferRenderSynchronizer, AV,SampleBuffer,Render,Synchron,ize,r
	OBJC	CALayer, CA,Layer
	OBJC	CATextLayer, CA,Text,Layer
	OBJC	CATransaction, CA,Trans,a,ction
	OBJC	NSAppearance, NS,A,ppear,ance
	OBJC	NSApplication, NS,A,pplication
	OBJC	NSArray, NS,Array
	OBJC	NSButton, NS,Button
	OBJC	NSCharacterSet, NS,Character,Set
	OBJC	NSColor, NS,C,olor
	OBJC	NSCursor, NS,Cursor
	OBJC	NSData, NS,Data
	OBJC	NSFont, NS,F,ont
	OBJC	NSImage, NS,Image
	OBJC	NSImageSymbolConfiguration, NS,Image,Symbol,Configuration
	OBJC	NSImageView, NS,Image,View
	OBJC	NSJSONSerialization, NS,JSO,NS,erializ,ation
	OBJC	NSLocale, NS,Lo,cale
	OBJC	NSMenu, NS,M,enu
	OBJC	NSMenuItem, NS,M,enu,Item
	OBJC	NSMutableURLRequest, NS,Mut,able,URL,R,equest
	OBJC	NSObject, NS,Object
	OBJC	NSOpenPanel, NS,OpenPanel
	OBJC	NSOperationQueue, NS,O,per,ation,Q,ueue
	OBJC	NSProgressIndicator, NS,Prog,res,s,In,dica,tor
	OBJC	NSSlider, NS,Sli,der
	OBJC	NSString, NS,String
	OBJC	NSTextField, NS,Text,Field
	OBJC	NSTimer, NS,Time,r
	OBJC	NSTrackingArea, NS,Tr,ack,ing,A,rea
	OBJC	NSURL, NS,URL
	OBJC	NSURLSession, NS,URL,Session
	OBJC	NSURLSessionConfiguration, NS,URL,Session,Configuration
	OBJC	NSView, NS,View
	OBJC	NSWindow, NS,Window
	OBJC	UTType, UT,Type
	REGSEL
	REG	S_systemFontOfSize_weight_, systemF,ont,Of,Size:,weight:
	REG	S_monospacedDigitSystemFontOfSize_weight_, monospacedDigitSystemF,ont,Of,Size:,weight:
	REG	S_JSONObjectWithData_options_error_, JSON,Object,With,Data,:op,tion,s:error:
	REG	S_URLWithString_, URL,With,String,:
	REG	S_UTF8String, UTF8,String
	REG	S_CGColor, CGC,olor
	REG	S_URL, URL
	REG	S_URLByDeletingPathExtension, URL,ByD,ele,t,ing,PathExten,sion
	REG	S_absoluteString, absolute,String
	REG	S_activate, a,ctiv,ate
	REG	S_addItem_, add,Item,:
	REG	S_addItemWithTitle_action_keyEquivalent_, add,Item,With,Title,:a,ction,:keyEqui,val,ent,:
	REG	S_addSubview_, add,Subview:
	REG	S_addTrackingArea_, add,Tr,ack,ing,A,rea,:
	REG	S_alloc, al,loc
	REG	S_animator, anima,tor
	REG	S_appearanceNamed_, a,ppear,ance,Nam,ed:
	REG	S_arrayWithObject_, array,With,Object,:
	REG	S_assetTrack, as,set,Tr,ack
	REG	S_bounds, b,ound,s
	REG	S_buttonWithImage_target_action_, button,With,Image,:t,arget:,a,ction,:
	REG	S_cancelOperation_, c,ance,lO,per,ation,:
	REG	S_cell, cell
	REG	S_center, cen,ter
	REG	S_clickCount, clickCount
	REG	S_colorWithSRGBRed_green_blue_alpha_, c,olor,With,SRGBR,ed:,green:blue:alpha:
	REG	S_componentsSeparatedByString_, compon,ent,sSepar,ate,dBy,String,:
	REG	S_configurationWithPointSize_weight_, configur,ation,With,Po,in,t,Size:,weight:
	REG	S_currentEvent, current,Ev,ent
	REG	S_currentItem, current,Item
	REG	S_currentTime, current,Time
	REG	S_dataWithBytes_length_, data,With,By,tes,:,length,:
	REG	S_dataWithBytesNoCopy_length_freeWhenDone_, data,With,By,tes,NoCopy:,length,:freeWhenDone:
	REG	S_doubleValue, double,Value
	REG	S_draggingPasteboard, dragg,ing,Pasteboard
	REG	S_duration, dur,ation
	REG	S_fileURLWithPath_, file,URL,With,Path:
	REG	S_firstObject, first,Object
	REG	S_host, host
	REG	S_imageViewWithImage_, image,View,With,Image,:
	REG	S_imageWithSystemSymbolName_accessibilityDescription_, image,With,System,Symbol,N,ame,:accessibility,Description,:
	REG	S_initWithContentRect_styleMask_backing_defer_, initWith,Content,Rect:styleM,ask,:b,ack,ing,:def,er:
	REG	S_initWithData_, initWith,Data,:
	REG	S_initWithFrame_, initWith,Fr,ame,:
	REG	S_initWithRect_options_owner_userInfo_, initWith,Rect:op,tion,s:own,er:,use,r,In,fo:
	REG	S_initWithTitle_, initWith,Title,:
	REG	S_intValue, in,t,Value
	REG	S_isEnabled, is,En,able,d
	REG	S_isEqualToString_, is,EqualTo,String,:
	REG	S_isExternalPlaybackActive, is,Ex,ter,nalP,lay,b,ack,A,ctiv,e
	REG	S__isBufferedAirPlayActive, _,is,Buffer,ed,Air,P,lay,A,ctiv,e
	REG	S_isFileURL, is,File,URL
	REG	S_labelWithString_, label,With,String,:
	REG	S_lastPathComponent, lastPathCompon,ent
	REG	S_layer, lay,er
	REG	S_locationInWindow, loc,ation,In,Window
	REG	S_makeFirstResponder_, make,FirstResponder,:
	REG	S_makeKeyAndOrderFront_, makeKeyAndOr,der,Fr,ont,:
	REG	S_maxValue, max,Value
	REG	S_mediaType, media,Type
	REG	S_menu, m,enu
	REG	S_new, new
	REG	S_openPanel, open,Panel
	REG	S_path, path
	REG	S_pause, pa,use
	REG	S_play, p,lay
	REG	S_playerItemWithURL_, p,lay,er,Item,With,URL,:
	REG	S_playerLayerWithPlayer_, p,lay,er,Layer,With,Player,:
	REG	S_presentationSize, p,res,ent,ation,S,ize
	REG	S_readObjectsForClasses_options_, rea,d,Object,s,For,C,lass,es:op,tion,s:
	REG	S_registerForDraggedTypes_, register,For,Dragged,Type,s:
	REG	S_release, r,elease
	REG	S_respondsToSelector_, res,ponds,To,S,ele,c,tor,:
	REG	S_replaceCurrentItemWithPlayerItem_, replaceCurr,ent,Item,With,Player,Item,:
	REG	S_retain, reta,in
	REG	S_run, run
	REG	S_runModal, runModal
	REG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, scheduled,Time,r,With,Time,Interval:,t,arget:,select,or:,use,r,In,fo:repeats:
	REG	S_seekToTime_toleranceBefore_toleranceAfter_, seekTo,Time,:toler,ance,Be,for,e:toler,ance,Aft,er:
	REG	S_selectText_, select,Text,:
	REG	S_separatorItem, separa,tor,Item
	REG	S_setAction_, set,A,ction,:
	REG	S_setActivationPolicy_, set,A,ctiv,ation,Policy:
	REG	S_setAlignment_, set,Alignm,ent,:
	REG	S_setAllowedContentTypes_, set,Allowed,Content,Type,s:
	REG	S_setAlphaValue_, set,Alpha,Value,:
	REG	S_setAppearance_, set,A,ppear,ance,:
	REG	S_setAutoresizingMask_, set,Auto,res,iz,ing,M,ask,:
	REG	S_setBackgroundColor_, set,B,ack,gr,ound,C,olor,:
	REG	S_setBezeled_, set,Bezel,ed:
	REG	S_setBordered_, set,Bor,der,ed:
	REG	S_setClipsToBounds_, set,ClipsToB,ound,s:
	REG	S_setCollectionBehavior_, set,Colle,ction,Behavior:
	REG	S_setContentMinSize_, set,Content,M,in,Size:
	REG	S_setContentSize_, set,Content,Size:
	REG	S_setContentTintColor_, set,Content,T,in,tC,olor,:
	REG	S_setContents_, set,Content,s:
	REG	S_setContentsGravity_, set,Content,sGrav,ity:
	REG	S_setContentsRect_, set,Content,sRect:
	REG	S_setControlSize_, set,C,ontrol,Size:
	REG	S_setCornerCurve_, set,CornerCurve:
	REG	S_setCornerRadius_, set,CornerRadius:
	REG	S_setDelegate_, set,D,ele,g,ate:
	REG	S_setDisplayedWhenStopped_, set,Display,edWhenStopp,ed:
	REG	S_setDoubleValue_, set,Double,Value,:
	REG	S_setDrawsBackground_, set,DrawsB,ack,gr,ound,:
	REG	S_setEnabled_, set,En,able,d:
	REG	S_setFocusRingType_, set,FocusR,ing,Type,:
	REG	S_setFont_, set,F,ont,:
	REG	S_setFrameSize_, set,Fr,ame,Size:
	REG	S_setFrame_, set,Fr,ame,:
	REG	S_setFrameOrigin_, set,Fr,ame,Orig,in,:
	REG	S_setHidden_, set,Hidden,:
	REG	S_setHiddenUntilMouseMoves_, set,Hidden,UntilMo,use,Moves:
	REG	S_setImage_, set,Image,:
	REG	S_setKeyEquivalentModifierMask_, set,KeyEqui,val,ent,ModifierM,ask,:
	REG	S_setLayer_, set,Layer,:
	REG	S_setLineBreakMode_, set,L,in,eB,rea,kM,ode,:
	REG	S_setMainMenu_, set,Ma,in,M,enu,:
	REG	S_setMaxValue_, set,Max,Value,:
	REG	S_setMovableByWindowBackground_, set,Mov,able,By,Window,B,ack,gr,ound,:
	REG	S_setMuted_, set,Mut,ed:
	REG	S_setPlaceholderString_, set,Placehol,der,String,:
	REG	S_setScrollable_, set,Scroll,able,:
	REG	S_setState_, set,St,ate:
	REG	S_setStringValue_, set,String,Value,:
	REG	S_setStyle_, set,Style:
	REG	S_setSubmenu_, set,Subm,enu,:
	REG	S_setSymbolConfiguration_, set,Symbol,Configuration,:
	REG	S_setTarget_, set,T,arget:
	REG	S_setTextColor_, set,Text,C,olor,:
	REG	S_setTitle_, set,Title,:
	REG	S_setTitleVisibility_, set,Title,V,is,ibil,ity:
	REG	S_setTitlebarAppearsTransparent_, set,Title,barA,ppear,s,Trans,par,ent,:
	REG	S_setTolerance_, set,Toler,ance,:
	REG	S_setToolTip_, set,ToolTip:
	REG	S_setTrackFillColor_, set,Tr,ack,FillC,olor,:
	REG	S_setUsesSingleLineMode_, set,UsesS,ing,leL,in,eM,ode,:
	REG	S_setVolume_, set,Volume:
	REG	S_setWantsLayer_, set,Wants,Layer,:
	REG	S_setWindowsMenu_, set,Window,sM,enu,:
	REG	S_sharedApplication, sharedA,pplication
	REG	S_startAnimation_, startAnim,ation,:
	REG	S_status, status
	REG	S_stopAnimation_, stop,Anim,ation,:
	REG	S_stringByTrimmingCharactersInSet_, str,ing,ByTrimm,ing,Character,s,In,Set,:
	REG	S_stringForType_, str,ing,For,Type,:
	REG	S_stringValue, str,ing,Value
	REG	S_stringWithUTF8String_, str,ing,With,UTF8,String,:
	REG	S_timeControlStatus, t,ime,C,ontrol,Status
	REG	S_toggleFullScreen_, toggleFullScreen:
	REG	S_tracks, tr,ack,s
	REG	S_type, type
	REG	S_typeWithIdentifier_, type,With,Id,ent,ifi,er:
	REG	S_whitespaceAndNewlineCharacterSet, whi,tes,paceAndNewl,in,e,Character,Set
	REG	S_count, count
	REG	S_isHidden, is,Hidden
	REG	S_occlusionState, occlu,sion,St,ate
	REG	S_setPlayer_, set,Player,:
	REG	S_setRoutePickerButtonBordered_, set,RoutePicker,Button,Bor,der,ed:
	REG	S_setRoutePickerButtonColor_forState_, set,RoutePicker,Button,C,olor,:,for,St,ate:
	REG	S_initWithPlayerLayer_, initWith,Player,Layer,:
	REG	S_isPictureInPictureActive, is,Picture,In,Picture,A,ctiv,e
	REG	S_startPictureInPicture, start,Picture,In,Picture
	REG	S_stopPictureInPicture, stop,Picture,In,Picture
	REG	S_keyCode, keyC,ode
	REG	S_styleMask, styleM,ask
	REG	S_tag, tag
	REG	S_setTag_, set,Tag:
	REG	S_itemArray, item,Array
	REG	S_removeAllItems, removeAll,Item,s
	REG	S_removeTimeObserver_, remove,Time,Observ,er:
	REG	S_options, op,tion,s
	REG	S_displayName, d,is,p,lay,N,ame
	REG	S_asset, as,set
	REG	S_mediaSelectionGroupForMediaCharacteristic_, media,SelectionGroup,For,Media,Character,is,tic:
	REG	S_currentMediaSelection, current,Media,S,ele,ction
	REG	S_selectedMediaOptionInMediaSelectionGroup_, select,ed,Media,Op,tion,In,Media,SelectionGroup,:
	REG	S_selectMediaOption_inMediaSelectionGroup_, select,Media,Op,tion,:,in,Media,SelectionGroup,:
	REG	S_setDefaultRate_, set,DefaultR,ate:
	REG	S_setRate_, set,R,ate:
	REG	S_objectAtIndex_, objectAt,In,dex:
	REG	S_setContentView_, set,Content,View,:
	REG	S_size, s,ize
	REG	S_sliderWithTarget_action_, sli,der,With,T,arget:,a,ction,:
	REG	S_addRenderer_, add,Render,er:
	REG	S_enqueueSampleBuffer_, enq,ueue,SampleBuffer,:
	REG	S_displayIfNeeded, d,is,p,lay,IfNeeded
	REG	S_flush, flush
	REG	S_flushWithRemovalOfDisplayedImage_completionHandler_, flush,With,Remo,val,Of,Display,ed,Image,:,completionHandler:
	REG	S_isReadyForDisplay, is,Ready,For,Display
	REG	S_isReadyForMoreMediaData, is,Ready,For,More,Media,Data
	REG	S_requestMediaDataWhenReadyOnQueue_usingBlock_, r,equest,Media,Data,When,Ready,OnQ,ueue,:us,ing,Block,:
	REG	S_sampleBufferRenderer, sa,mple,Buffer,Render,er
	REG	S_setAudioTimePitchAlgorithm_, set,Audio,Time,PitchAlgorithm:
	REG	S_setRate_time_, set,R,ate:,t,ime,:
	REG	S_stopRequestingMediaData, stop,R,equest,ing,Media,Data
	REG	S_bytes, by,tes
	REG	S_cancel, c,ance,l
	REG	S_dataTaskWithRequest_, data,T,ask,With,R,equest,:
	REG	S_defaultSessionConfiguration, default,Session,Configuration
	REG	S_length, length
	REG	S_requestWithURL_, r,equest,With,URL,:
	REG	S_response, res,ponse
	REG	S_resume, res,ume
	REG	S_sessionWithConfiguration_delegate_delegateQueue_, ses,sion,With,Configuration,:d,ele,g,ate:,d,ele,g,ate,Q,ueue,:
	REG	S_setAssumesHTTP3Capable_, set,Assumes,HTTP,3Cap,able,:
	REG	S_setHTTPBody_, set,HTTP,Body:
	REG	S_setHTTPMethod_, set,HTTP,Method:
	REG	S_setTimeoutInterval_, set,Time,out,Interval:
	REG	S_setUnderlyingQueue_, set,Un,der,ly,ing,Q,ueue,:
	REG	S_setValue_forHTTPHeaderField_, set,Value,:,for,HTTPHeaderField:
	REG	S_statusCode, statusC,ode
	REG	S_valueForHTTPHeaderField_, val,ue,For,HTTPHeaderField:
	REG	S_URLWithString_relativeToURL_, URL,With,String,:relativeTo,URL,:
	REG	S_addPeriodicTimeObserverForInterval_queue_usingBlock_, add,Periodic,Time,Observer,For,Interval:,q,ueue,:us,ing,Block,:
	REG	S_addSublayer_, add,Sub,lay,er:
	REG	S_backingScaleFactor, b,ack,ing,S,cale,Fac,tor
	REG	S_begin, beg,in
	REG	S_commit, commit
	REG	S_currentLocale, current,Lo,cale
	REG	S_localizedStringForLanguageCode_, loc,al,ize,d,String,For,LanguageC,ode,:
	REG	S_preferredFrameSize, preferredFr,ame,S,ize
	REG	S_setAlignmentMode_, set,Alignm,ent,M,ode,:
	REG	S_setContentsScale_, set,Content,sS,cale,:
	REG	S_setDisableActions_, set,D,is,able,A,ction,s:
	REG	S_setFontSize_, set,F,ont,Size:
	REG	S_setShadowOpacity_, set,ShadowOpac,ity:
	REG	S_setString_, set,String,:
	REG	S_setWrapped_, set,Wrapp,ed:
	REG	S_setAffineTransform_, set,Aff,in,e,Trans,for,m:
	REG	S_setBounds_, set,B,ound,s:
	REG	S_setPosition_, set,Posi,tion,:
	REG	S_setVideoGravity_, set,VideoGrav,ity:
	REG	S_initWithSampleBufferDisplayLayer_playbackDelegate_, initWith,SampleBuffer,Display,Layer,:p,lay,b,ack,D,ele,g,ate:
	REG	S_initWithContentSource_, initWith,Content,Source:
	REGACT
	REG	S_URLSession_dataTask_didReceiveData_, URL,Session,:,data,T,ask,:didReceive,Data,:
	REG	S_URLSession_task_didCompleteWithError_, URL,Session,:t,ask,:didCo,mple,te,With,Error:
	REG	S_acceptsFirstResponder, accepts,FirstResponder
	REG	S_act_aonly_, act_,aonly:
	REG	S_act_back_, act_,b,ack,:
	REG	S_act_focus_, act_,focus:
	REG	S_act_fwd_, act_,fwd:
	REG	S_act_mute_, act_,mute:
	REG	S_act_open_, act_,open,:
	REG	S_act_option_, act_,op,tion,:
	REG	S_act_pip_, act_,pip:
	REG	S_act_play_, act_,p,lay,:
	REG	S_act_seek_, act_,seek:
	REG	S_act_speed_, act_,spe,ed:
	REG	S_act_stop_, act_,stop,:
	REG	S_act_tick_, act_,tick:
	REG	S_act_toggle_, act_,toggle:
	REG	S_act_vol_, act_,vol:
	REG	S_act_voldown_, act_,voldown:
	REG	S_act_volup_, act_,volup:
	REG	S_application_openURLs_, a,pplication,:,open,URL,s:
	REG	S_applicationShouldTerminateAfterLastWindowClosed_, a,pplication,ShouldTerm,in,ate,Af,ter,Last,Window,Clos,ed:
	REG	S_control_textView_doCommandBySelector_, c,ontrol,:text,View,:doCommandByS,ele,c,tor,:
	REG	S_copy_, copy:
	REG	S_cut_, cut:
	REG	S_draggingEntered_, dragg,ing,En,ter,ed:
	REG	S_hide_, hide:
	REG	S_hideOtherApplications_, hideOtherA,pplication,s:
	REG	S_keyDown_, keyDown:
	REG	S_menuNeedsUpdate_, m,enu,NeedsUpd,ate:
	REG	S_mouseDown_, mo,use,Down:
	REG	S_mouseMoved_, mo,use,Mov,ed:
	REG	S_orderFrontStandardAboutPanel_, or,der,Fr,ont,StandardAboutPanel:
	REG	S_paste_, paste:
	REG	S_performClose_, per,for,mClose:
	REG	S_performDragOperation_, per,for,mDragO,per,ation,:
	REG	S_performMiniaturize_, per,for,mM,in,iatur,ize,:
	REG	S_performZoom_, per,for,mZoom:
	REG	S_pictureInPictureController_didTransitionToRenderSize_, picture,InPictureController,:did,Trans,i,tion,To,Render,Size:
	REG	S_pictureInPictureController_setPlaying_, picture,InPictureController,:,set,P,lay,ing,:
	REG	S_pictureInPictureController_skipByInterval_completionHandler_, picture,InPictureController,:skipBy,Interval:,completionHandler:
	REG	S_pictureInPictureControllerIsPlaybackPaused_, picture,InPictureController,IsP,lay,b,ack,Paus,ed:
	REG	S_pictureInPictureControllerTimeRangeForPlayback_, picture,InPictureController,Time,Range,For,P,lay,b,ack,:
	REG	S_redo_, redo:
	REG	S_routePickerViewWillBeginPresentingRoutes_, routePicker,View,WillBeg,in,P,res,ent,ing,Rou,tes,:
	REG	S_selectAll_, select,All:
	REG	S_terminate_, ter,m,in,ate:
	REG	S_undo_, undo:
	REG	S_unhideAllApplications_, unhideAllA,pplication,s:
	REG	S_windowDidResize_, w,in,dowDidRes,ize,:
.endm
.set Lnreg, 0
.macro REG sym, parts:vararg
	.set	\sym, B_REG + 8 * Lnreg
	.set	Lnreg, Lnreg + 1
.endm
.macro REGSEL
	.set	B_SEL, B_REG + 8 * Lnreg      ; the first selector
.endm
.macro REGCLS
	.set	B_CLS, B_REG + 8 * Lnreg      ; the first class
.endm
.macro REGACT
	.set	B_ACT, B_REG + 8 * Lnreg      ; the first selector of the UI programs' actions and methods
.endm
.macro FN name, a, b, c, d, e, f, g, h, i, j, k, l, m ; its stub jumps through the slot
	REG	F_\name
	.pushsection __TEXT,__text,regular,pure_instructions
_\name:
	ldr	x16, [x27, #F_\name]
	br	x16
	.popsection
.endm
	REGISTRY
	.purgem	REG
	.purgem	REGSEL
	.purgem	REGCLS
	.purgem	REGACT
	.purgem	FN
.equ B_ENG,                      B_REG + 8 * Lnreg ; the engine (media queue)
.equ E_SYNC,                     B_ENG    ; AVSampleBufferRenderSynchronizer
.equ E_AR,                       E_SYNC + 8 ; its sound renderer
.equ E_VR,                       E_AR + 8 ; and picture renderer
.equ E_SESSION,                  E_VR + 8 ; the NSURLSession; its delegate calls run on the media queue
.equ E_WAITGEN,                  E_SESSION + 8 ; w: the newest wait for a first picture
.equ E_SLOW,                     E_WAITGEN + 4 ; w: paused when net_tick last ran: its ticks slow down and no picture is held to its lead
.equ E_SUBOBS,                   E_WAITGEN + 8 ; the subtitles' periodic observer, while a subtitle track is shown
.equ E_HOLDGEN,                  E_SUBOBS + 8 ; w: the newest hold sent to the clock queue, the one it started, the one it finished
.equ E_HOLDGO,                   E_HOLDGEN + 4
.equ E_HOLDDONE,                 E_HOLDGO + 4
.equ E_CLR,                      E_HOLDDONE + 8 ; from here, cleared when media closes
.equ E_PARENT,                   E_CLR    ; the CMBlockBuffer over the mapped file
.equ E_MAP,                      E_PARENT + 8
.equ E_LEN,                      E_MAP + 8
.equ E_VT,                       E_LEN + 8 ; the tracks playing: picture and sound
.equ E_AT,                       E_VT + 8
.equ E_DURMS,                    E_AT + 8
.equ E_MTS,                      E_DURMS + 8 ; w: movie timescale
.equ E_NTR,                      E_MTS + 4 ; w: tracks read
.equ E_HOLD,                     E_NTR + 4 ; w: the clock waits for the first picture
.equ E_WAITN,                    E_HOLD + 4 ; w: polls left
.equ E_ISO,                      E_WAITN + 4 ; w: an ISO file, not QuickTime
.equ E_GEN,                      E_ISO + 4 ; w: the play it opened
.equ E_NET,                      E_GEN + 4 ; w: the media comes as streams
.equ E_WANTV,                    E_NET + 4 ; w: a picture is coming: the clock waits for it
.equ E_TGTMS,                    E_WANTV + 4 ; the last seek's target, ms
.equ E_T0,                       E_TGTMS + 8 ; HLS: the timeline's origin in 90 kHz units (the first PTS less its segment's start)
.equ E_T0S,                      E_T0 + 8
.equ E_MASTER,                   E_T0S + (8 << HLS_T0_BITS) ; the master playlist and its URL
.equ E_MURL,                     E_MASTER + 8
.equ E_BPS,                      E_MURL + 8 ; the measured network speed, bits per second
.equ E_FIRSTMS,                  E_BPS + 8 ; the first picture shown after a seek, ms (+1), 0 none yet; bit 63: ready on a poll already
.equ E_LIVE,                     E_FIRSTMS + 8 ; w: a YouTube broadcast
.equ E_PREV,                     E_LIVE + 4 ; w: a stream's seek showed its first picture already
.equ E_SUBT,                     E_LIVE + 8 ; the subtitle track shown, 0 none
.equ E_SUBN,                     E_SUBT + 8 ; its next cue, taken early (retained)
.equ E_SUBEND,                   E_SUBN + 8 ; when the cue shown ends, track units
.equ E_SUBON,                    E_SUBEND + 8 ; w: a cue is shown
.equ E_M4A,                      E_SUBON + 4 ; w: 1 while AudioFileStream tries an M4A, 2 once it could not
.equ E_CCT,                      E_SUBON + 4 + 4 ; the CC1 caption track, made when picked
.equ E_CC,                       E_CCT + 8 ; its CEA-608 decoder and the captions waiting for presentation order (CC_*)
.equ CC_MODE,                    0        ; w: 0 pop-on, 1 roll-up, 2 paint-on
.equ CC_ROWS,                    4        ; w: roll-up's rows
.equ CC_LAST,                    8        ; w: the last control pair, sent twice
.equ CC_CHAN,                    12       ; w: the channel the text is for, 1 = CC2
.equ CC_D,                       16       ; the shown caption: w length, bytes
.equ CC_N,                       CC_D + 128 ; and the one being loaded (pop-on)
.equ CC_QN,                      CC_N + 128 ; w: captions waiting, by presentation time: {pts, w pairs, pairs[8]}[6]
.equ CC_Q,                       CC_QN + 8
.equ CC_E,                       32
.equ CC_SIZE,                    CC_Q + 6 * CC_E
.equ E_MSEQ,                     (E_CC + CC_SIZE + 7) & ~7
.equ E_MTIME,                    E_MSEQ + 8
.equ E_ST,                       (E_MTIME + 8 + 63) & ~63 ; Stream[STREAMS]
.equ E_TR,                       (E_ST + STREAMS * ST_SIZE + 63) & ~63 ; Track[TRACKS]
.equ E_CLRN,                     E_TR + TRACKS * TR_SIZE - E_CLR
.equ B_RQT,                      E_TR + TRACKS * TR_SIZE ; {task, record}[RQS]: requests running (media queue)
.equ B_LTPATH,                   B_RQT + 16 * RQS ; char[1024], This Mac's file, for AVPlayer when the engine cannot play it (main)
.equ B_LTVURL,                   B_LTPATH + 1024 ; char[4096], YouTube's own HLS, for AirPlay, or "" (main)
.equ B_VISITOR,                  B_LTVURL + 4096 ; char[288], the visitorData member once YouTube gave it (lock)
.equ B_SUBL,                     B_VISITOR + 288 ; the subtitle layer, made on first use (main)
.equ B_PIC,                      B_SUBL + 8 ; w: the picture's turn, width and height, as the view lays it out (main)
.equ B_PIPE,                     B_PIC + 16 ; the engine picture's Picture in Picture controller, made on first use (main)
.equ B_AIRK,                     B_PIPE + 8 ; w: what the dormant AVPlayer would play over AirPlay: 0 nothing, 1 B_LTPATH's file, 2 its URL, 3 B_LTVURL (main)
.equ B_VTW,                      B_AIRK + 8 ; eng_init's parameter sets: pointers, sizes, the format, a session (media queue)
.equ B_AFF,                      B_VTW + 64 ; pic_layout's turn: a, b, c, d, tx, ty (main)
.equ B_TIMEB,                    B_AFF + 48 ; show_time's text (main)
.equ B_MNEXT,                    B_TIMEB + 32 ; media_next's line after the one found
.equ B_UJ,                       B_MNEXT + 8 ; char[4096], url_join's URI (media queue)
.equ B_SIZE,                     B_UJ + 4096
.equ GB_SIZE,                    ((G_SIZE + 15) & ~15) + B_SIZE ; G, then B, in one zeroed block from main

	.text

; ---- Frames and entry ----

; Lpro<n> — the rest of a FRAME prologue: frame pointer, room for n register pairs below it, and the pairs.
	.p2align 2
Lpro4:
	mov	x29, sp
	sub	sp, sp, #64
	stp	x25, x26, [x29, #-64]
	b	Lsave3
Lpro3:
	mov	x29, sp
	sub	sp, sp, #48
Lsave3:
	stp	x23, x24, [x29, #-48]
	b	Lsave2
Lpro2:
	mov	x29, sp
	sub	sp, sp, #32
Lsave2:
	stp	x21, x22, [x29, #-32]
	b	Lsave1
Lpro1:
	mov	x29, sp
	sub	sp, sp, #16
Lsave1:
	stp	x19, x20, [x29, #-16]
	ret
Lpro4m:
	mov	x29, sp
	sub	sp, sp, #64
	stp	x25, x26, [x29, #-64]
	b	Lsave3m
Lpro3m:
	mov	x29, sp
	sub	sp, sp, #48
Lsave3m:
	stp	x23, x24, [x29, #-48]
	b	Lsave2m
Lpro2m:
	mov	x29, sp
	sub	sp, sp, #32
Lsave2m:
	stp	x21, x22, [x29, #-32]
	b	Lsave1m
Lpro1m:
	mov	x29, sp
	sub	sp, sp, #16
Lsave1m:
	stp	x19, x20, [x29, #-16]
	mov	x19, x0
	mov	x20, x1
	ret

; Lret<n> — epilogue of a FRAME with n pairs (Lnil4: returning 0).
Lnil4:
	mov	x0, #0
Lret4:
	ldp	x25, x26, [x29, #-64]
Lret3:
	ldp	x23, x24, [x29, #-48]
Lret2:
	ldp	x21, x22, [x29, #-32]
Lret1:
	ldp	x19, x20, [x29, #-16]
Lret0:
	mov	sp, x29
	ldp	x29, x30, [sp], #16
	ret

; L<selector> — objc_msgSend with that selector: stubs for the selectors sent most.
LS_UTF8String:
	ldr	x1, [x27, #S_UTF8String]
	b	_objc_msgSend
LS_stopRequestingMediaData:
	ldr	x1, [x27, #S_stopRequestingMediaData]
	b	_objc_msgSend
LS_release:
	ldr	x1, [x27, #S_release]
	b	_objc_msgSend
LS_response:
	ldr	x1, [x27, #S_response]
	b	_objc_msgSend
LS_setValue_forHTTPHeaderField_:
	ldr	x1, [x27, #S_setValue_forHTTPHeaderField_]
	b	_objc_msgSend
LS_retain:
	ldr	x1, [x27, #S_retain]
	b	_objc_msgSend
LS_absoluteString:
	ldr	x1, [x27, #S_absoluteString]
	b	_objc_msgSend
LS_bounds:
	ldr	x1, [x27, #S_bounds]
	b	_objc_msgSend
LS_setRate_:
	ldr	x1, [x27, #S_setRate_]
	b	_objc_msgSend
LS_statusCode:
	ldr	x1, [x27, #S_statusCode]
	b	_objc_msgSend
LS_flush:
	ldr	x1, [x27, #S_flush]
	b	_objc_msgSend
LS_currentItem:
	ldr	x1, [x27, #S_currentItem]
	b	_objc_msgSend
LS_status:
	ldr	x1, [x27, #S_status]
	b	_objc_msgSend
LS_setMuted_:
	ldr	x1, [x27, #S_setMuted_]
	b	_objc_msgSend

; vm_entry — a method that is a UI program (x9): vm_run with x28 = G and x27 = B.
vm_entry:
	adr	x16, vm_run
; tramp — run x16 with x28 = G and x27 = B, keeping the caller's.
tramp:
	stp	x27, x28, [sp, #-32]!
	str	x30, [sp, #16]
	ADDR	x28, Ldl
	ldp	x28, x27, [x28, #8]
	blr	x16
	ldr	x30, [sp, #16]
	ldp	x27, x28, [sp], #32
	ret

; Strings used in more than one place.
	.pushsection __DATA,__data
Ls_slash:	.ascii	"/"
Ls_empty:	.byte	0
Ls_sep:	.asciz	"://"
Ls_xstream:	.asciz	"#EXT-X-STREAM-INF:"
Ls_taudio:	.asciz	"TYPE=AUDIO"
Ls_uri:	.asciz	"URI="
Ls_bytes:	.asciz	"bytes=%lld-%lld"
Ls_group:	.asciz	"GROUP-ID="
Ls_tsubs:	.asciz	"TYPE=SUBTITLES"
Ls_xmedia:	.asciz	"#EXT-X-MEDIA:"
Ls_vmp4:	.asciz	"\"video/mp4"
Ls_gvideo:	.asciz	"googlevideo"
Ls_aac:	.asciz	"mp4a.40.2"
Ls_url:	.asciz	"\"url\":"
Ls_range:	.asciz	"Range"
Ls_qend:	.asciz	"&?/#"
	.popsection

; ---- Small utilities ----

; buf_cb(data, size, nmemb, buf) — append to a NUL-terminated buffer {data, len} of at most BUF_MAX bytes.
	ENTRY	buf_cb
	FRAME	2
	mul	x19, x1, x2
	mov	x20, x0
	mov	x21, x3
	ldp	x0, x22, [x21]
	add	x1, x22, x19
	mov	x9, #BUF_MAX
	cmp	x1, x9
	b.hi	Lbc_fail
	add	x1, x1, #1
	bl	_realloc
	cbz	x0, Lbc_fail
	add	x9, x22, x19
	stp	x0, x9, [x21]
	add	x0, x0, x22
	mov	x1, x20
	mov	x2, x19
	bl	_memcpy
	strb	wzr, [x0, x19]
	mov	x0, x19
	b	Lret2
Lbc_fail:
	mov	x0, #0
	b	Lret2

; strtol10(text) -> its decimal number.
strtol10:
	mov	x1, #0
	mov	w2, #10
	b	_strtol

; nextstr(p) -> the string after p in a packed list.
nextstr:
	FRAME	1, 0, 1
	bl	_strlen
	add	x0, x19, x0
	add	x0, x0, #1
	b	Lret1

; lock / unlock — take or release G's lock.
lock:
	add	x0, x28, #G_LOCK
	JUMPF	os_unfair_lock_lock
unlock:
	add	x0, x28, #G_LOCK
	JUMPF	os_unfair_lock_unlock

; post_main(work, context) — run work(context) on the main thread.
post_main:
	mov	x2, x0
	MAINQ	x0
	b	_dispatch_async_f

; ---- Playing a link: main -> worker -> main ----

; play_resolve(job) — resolve the link, report to main.
	ENTRY	play_resolve
	FRAME	2, 0, 1
	bl	_objc_autoreleasePoolPush
	mov	x21, x0
	mov	x0, x19
	bl	resolve
	str	w0, [x19, #JOB_RESULT]
	mov	x0, x21
	bl	_objc_autoreleasePoolPop
	adr	x0, ui_play_done
	mov	x1, x19
	bl	post_main
	b	Lret2

; mkurl(cstr) -> an autoreleased NSURL, or nil.
mkurl:
	FRAME	0
	bl	mkstr
	mov	x2, x0
	CLASS	x0, NSURL
	SEND	S_URLWithString_
	b	Lret0

; make_item(url) -> a retained AVPlayerItem for a URL string, or nil if it is not one.
make_item:
	FRAME	0
	bl	mkurl
	cbz	x0, Lret0
	mov	x2, x0
	CLASS	x0, AVPlayerItem
	SEND	S_playerItemWithURL_
	SEND	S_retain
	b	Lret0

; ---- ISO BMFF boxes ----

; box_find(p, end, type) — x0 = the payload of the first box of that type in [p, end), x1 = its end; x0 = 0 if none. Uses x9-x13 only.
box_find:
	add	x9, x0, #8                ; the payload, after size and type
	cmp	x9, x1
	b.hi	Lbf_none
	sub	x13, x1, x0               ; room left
	ldr	w10, [x0]
	rev	w10, w10                  ; size, big-endian
	cbnz	w10, Lbf_large
	mov	x10, x13                  ; 0: to the end
Lbf_large:
	cmp	x10, #1
	b.ne	Lbf_sized
	add	x9, x0, #16               ; 1: a 64-bit size follows the type
	cmp	x9, x1
	b.hi	Lbf_none
	ldr	x10, [x0, #8]
	rev	x10, x10
Lbf_sized:
	sub	x11, x9, x0
	cmp	x10, x11
	b.lo	Lbf_none                  ; shorter than its header
	cmp	x10, x13
	b.hi	Lbf_none                  ; past the end
	add	x11, x0, x10
	ldr	w12, [x0, #4]
	mov	x0, x11
	cmp	w12, w2
	b.ne	box_find
	mov	x0, x9
	mov	x1, x11
	ret
Lbf_none:
	mov	x0, #0
	ret

; ---- Resolver: a link or search text -> media URL and metadata (worker queue) ----

; is_link(text) — w0 = 1 for a link (no spaces, with a '.' and a '/'), 0 for search words.
is_link:
	mov	w1, #0                    ; bit 0: a '.', bit 1: a '/'
Lil_next:
	ldrb	w2, [x0], #1
	cmp	w2, #' '
	b.eq	Lil_no
	cbz	w2, Lil_end
	cmp	w2, #'.'
	cset	w3, eq
	orr	w1, w1, w3
	cmp	w2, #'/'
	cset	w3, eq
	orr	w1, w1, w3, lsl #1
	b	Lil_next
Lil_end:
	cmp	w1, #3
	cset	w0, eq
	ret
Lil_no:
	mov	w0, #0
	ret

; video_id(link, out[12]) -> the 11-character id after "v=", "/shorts/", "/embed/", "/live/" or "youtu.be/" (copied to out), else the link.
	.pushsection __DATA,__data
Lid_keys:	.asciz	"v="
	.asciz	"/shorts/"
	.asciz	"/embed/"
	.asciz	"/live/"
	.asciz	"youtu.be/"
	.byte	0
	.popsection
video_id:
	FRAME	3, 0, 1
	GADDR	x21, Lid_keys
Lvi_key:
	ldrb	w9, [x21]
	cbz	w9, Lvi_self
	mov	x0, x21
	bl	_strlen
	mov	x23, x0
	mov	x0, x19
	mov	x1, x21
	bl	_strstr
	add	x21, x21, x23
	add	x21, x21, #1              ; the next key
	cbz	x0, Lvi_key
	add	x22, x0, x23              ; past the key
	mov	x0, x22
	GADDR	x1, Ls_qend
	bl	_strcspn
	cmp	x0, #11
	b.lo	Lvi_key
	mov	x0, x20
	mov	x1, x22
	mov	x2, #12
	bl	_strlcpy
	mov	x0, x20
	b	Lret3
Lvi_self:
	mov	x0, x19
	b	Lret3

; jfind(json, key) -> the value after the first key (written with its quotes and colon), or NULL.
jfind:
	FRAME	1
	mov	x19, x1
	cbz	x0, Lret1
	bl	_strstr
	cbz	x0, Lret1
	mov	x20, x0
	mov	x0, x19
	bl	_strlen
	add	x0, x20, x0
	b	Lret1

; jstr(value, out, cap) — decode the JSON string at value into out; "" when it is not one.
jstr:
	FRAME	2, 0, 1
	mov	x21, x2
	strb	wzr, [x20]
	cbz	x19, Lret2
	ldrb	w9, [x19]
	cmp	w9, #'"'
	b.ne	Lret2
	add	x9, x19, #1
Ljs_scan:
	ldrb	w10, [x9], #1
	cbz	w10, Lret2                ; unterminated
	cmp	w10, #'\\'
	b.ne	Ljs_quote
	ldrb	w10, [x9], #1
	cbz	w10, Lret2
	b	Ljs_scan
Ljs_quote:
	cmp	w10, #'"'
	b.ne	Ljs_scan
	CLASS	x0, NSData
	mov	x2, x19
	sub	x3, x9, x19               ; the literal with both quotes
	mov	w4, #0
	SEND	S_dataWithBytesNoCopy_length_freeWhenDone_
	mov	x2, x0
	CLASS	x0, NSJSONSerialization
	mov	x3, #4                    ; NSJSONReadingFragmentsAllowed
	mov	x4, #0
	SEND	S_JSONObjectWithData_options_error_
	SEND	S_UTF8String
	cbz	x0, Lret2
	mov	x1, x0
	mov	x0, x20
	mov	x2, x21
	bl	_strlcpy
	b	Lret2

; jesc(out[1024], text) — text escaped for a JSON string; control characters become spaces.
jesc:
	add	x9, x0, #1016
Lje_next:
	ldrb	w10, [x1], #1
	cbz	w10, Lje_end
	cmp	x0, x9
	b.hs	Lje_end
	cmp	w10, #' '
	b.hs	Lje_char
	mov	w10, #' '
Lje_char:
	cmp	w10, #'"'
	b.eq	Lje_esc
	cmp	w10, #'\\'
	b.ne	Lje_put
Lje_esc:
	mov	w11, #'\\'
	strb	w11, [x0], #1
Lje_put:
	strb	w10, [x0], #1
	b	Lje_next
Lje_end:
	strb	wzr, [x0]
	ret

; resolve_file(job) -> PLAY_OK: a file on this Mac, by path or file URL; its name is the title.
resolve_file:
	VM	Lp_rfile
	.pushsection __DATA,__data
Lp_rfile:
	IMM	KIND_FILE
	STW	0, JOB_KIND
	GL	0
	LDX	JOB_QUERY
	SL	1
	LDB	0
	EQ	'/'
	JNZ	Lp_rfile_path
	NCALL	mkurl, "=b"               ; a file URL: its path becomes the query
	MSG	S_path, "="
	MSG	S_UTF8String, "="
	JZ	Lp_rfile_path
	CALL	F_strdup, "=V"
	JZ	Lp_rfile_path
	SL	2
	CALL	F_free, "b"
	GL	2
	STX	0, JOB_QUERY
	SL	1
	HERE	Lp_rfile_path
	NCALL	mkstr, "=b"
	SL	2
	CLS	NSURL
	MSG	S_fileURLWithPath_, "=c"
	SL	3
	MSG	S_absoluteString, "="
	MSG	S_UTF8String, "="
	SL	2
	GL	0
	ADDH	JOB_URL
	SL	4
	CALL	F_strlcpy, "ecH"
	.short	4096
	NCALL	url_title, "=da"
	OP_END
	.popsection

; resolve_web(job) -> PLAY_OK for any other web address (https when it has no scheme), played as it is; PLAY_FAILED if it is not one.
	.pushsection __DATA,__data
Ls_https:	.asciz	"https://"
Ls_notweb:	.asciz	"this is not a web address"
	.popsection
resolve_web:
	VMT
	IMM	KIND_WEB
	STW	0, JOB_KIND
	GL	0
	LDX	JOB_QUERY
	SL	1                         ; b: the address as typed
	GL	0
	ADDH	JOB_URL
	SL	2                         ; c: where its URL goes
	CALL	F_strstr, "=bP"
	.long	Ls_sep - Lvm_base
	JNZ	Lrw_copy
	CALL	F_strlcpy, "cPH"          ; no scheme: https
	.long	Ls_https - Lvm_base
	.short	4096
	GL	2
	ADDI	8
	SL	2
	HERE	Lrw_copy
	CALL	F_strlcpy, "cbH"
	.short	4088
	GL	0
	ADDH	JOB_URL
	NCALL	mkurl, "=V"
	JZ	Lrw_bad
	SL	3                         ; d: the URL
	MSG	S_host, "="               ; the site, where an artist would be
	MSG	S_UTF8String, "="
	JZ	Lrw_title
	SL	4
	GL	0
	ADDH	JOB_TRACK + T_ARTIST
	SL	5
	CALL	F_strlcpy, "feH"
	.short	256
	HERE	Lrw_title
	NCALL	url_title, "=da"
	OP_END
	HERE	Lrw_bad
	LEA	Ls_notweb
	STX	0, JOB_ERR
	IMM	PLAY_FAILED
	OP_END
	.p2align 2

; url_title(url, job) -> PLAY_OK, with the URL's last path component, without its extension, as the job's title.
url_title:
	VM	Lp_utitle
	.pushsection __DATA,__data
Lp_utitle:
	GL	0
	MSG	S_URLByDeletingPathExtension, "="
	MSG	S_lastPathComponent, "="
	MSG	S_UTF8String, "="
	JZ	Lp_utitle_ok
	SL	2
	GL	1
	ADDH	JOB_TRACK + T_TITLE
	SL	3
	CALL	F_strlcpy, "dcH"
	.short	512
	HERE	Lp_utitle_ok
	IMM	PLAY_OK
	OP_END
	.popsection

; resolve's frame, which api fills.
	.equ RS_BUF,	16                ; {data, len}
	.equ RS_VIS,	32                ; char[288], the visitorData member, or ""
	.equ RS_ID,	320               ; char[16]
	.equ RS_ESC,	336               ; char[1024]
	.equ RS_TAIL,	1360              ; char[1280], the request after its context
	.equ RS_CPN,	2640              ; char[32]
	.equ RS_SIZE,	2672

; api(endpoint, client, tail, frame) — POST to InnerTube as a client, into resolve's RS_BUF; w0 = 1 on success.
	.equ AP_NUM,	64                ; the name's number
	.equ AP_BODY,	72
api:
	FRAME	4, 80
	mov	x21, x0
	mov	x20, x1
	mov	x22, x2
	add	x23, x3, #RS_BUF
	add	x24, x3, #RS_VIS
	mov	x0, x20                   ; the client's fields: name, version (also a header), OS, its version, others, the name's number
	bl	nextstr
	str	x0, [sp]
	bl	nextstr
	mov	x26, x0
	str	x0, [sp, #8]
	bl	nextstr
	str	x0, [sp, #16]
	bl	nextstr
	str	x0, [sp, #24]
	bl	nextstr
	str	x0, [sp, #32]
	bl	nextstr
	str	x0, [sp, #AP_NUM]
	stp	x20, x24, [sp, #40]
	str	x22, [sp, #56]
	add	x0, sp, #AP_BODY
	CSTR	x1, "{\"context\":{\"client\":{\"clientName\":\"%s\",\"clientVersion\":\"%s\",\"osName\":\"%s\",\"osVersion\":\"%s\",%s\"hl\":\"en\",\"gl\":\"US\",\"userAgent\":\"%s\"%s}}%s"
	bl	_asprintf
	mov	w22, #0
	ldr	x9, [sp, #AP_BODY]
	cbz	x9, Lapi_free
	mov	w25, #2                   ; attempts: a kept-alive connection may have been dropped
Lapi_try:
	mov	x0, x21
	bl	mkreq
	cbz	x0, Lapi_free
	mov	x19, x0
	CSTR	x0, "POST"
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setHTTPMethod_
	ldr	x0, [sp, #AP_BODY]
	bl	_strlen
	mov	x3, x0
	ldr	x2, [sp, #AP_BODY]
	CLASS	x0, NSData
	SEND	S_dataWithBytes_length_
	mov	x2, x0
	mov	x0, x19
	SEND	S_setHTTPBody_
	mov	x0, x19                   ; headers: every request's, the client's, the endpoint's field mask
	ADDR	x1, Lapi_headers
	bl	hdrs
	ldr	x1, [sp, #AP_NUM]
	mov	x2, x26
	bl	ythdrs
	mov	x0, x21
	bl	nextstr
	mov	x1, x0
	mov	x0, x19
	bl	hdrs
	mov	x0, x20                   ; and the client's user agent
	bl	mkstr
	mov	x22, x0
	CSTR	x0, "User-Agent"
	bl	mkstr
	mov	x3, x0
	mov	x2, x22
	mov	x0, x19
	SEND	S_setValue_forHTTPHeaderField_
	mov	x0, x19                   ; Google's front end speaks QUIC: one round trip less to connect
	mov	w2, #1
	SEND	S_setAssumesHTTP3Capable_
	mov	x0, x19
	mov	x1, x23
	bl	fetch
	mov	w22, w0
	cbnz	w0, Lapi_free
	subs	w25, w25, #1
	b.ne	Lapi_try
Lapi_free:
	ldr	x0, [sp, #AP_BODY]
	bl	_free
	mov	w0, w22
	b	Lret4

; ythdrs(request, number, version) — YouTube's client headers.
ythdrs:
	VM	Lp_ythdrs
	.pushsection __DATA,__data
Lp_ythdrs:
	NCALL	mkstr, "=b"
	SL	3
	GL	0
	MSG	S_setValue_forHTTPHeaderField_, "dS"
	.asciz	"X-YouTube-Client-Name"
	NCALL	mkstr, "=c"
	SL	3
	GL	0
	MSG	S_setValue_forHTTPHeaderField_, "dS"
	.asciz	"X-YouTube-Client-Version"
	OP_END
	.popsection

; within(needle) — the needle in parse_player's current format [x21, x25), or NULL.
within:
	stp	x29, x30, [sp, #-16]!
	mov	x1, x0
	mov	x0, x21
	bl	_strstr
	ldp	x29, x30, [sp], #16
	cmp	x0, x25
	csel	x0, x0, xzr, lo
	ret

; jnum(json, key) -> the number after key, quoted or not (0 if absent).
jnum:
	FRAME	0
	bl	jfind
	cbz	x0, Lret0
	ldrb	w9, [x0]
	cmp	w9, #'"'
	cinc	x0, x0, eq
	bl	strtol10
	b	Lret0

; fmt_info(start, end, fmt) — a format's init and index byte ranges, bitrate and codecs, from its JSON [start, end).
	.pushsection __DATA,__data
Lk_start:	.asciz	"\"start\":"
Lk_end:	.asciz	"\"end\":"
	.popsection
fmt_info:
	FRAME	4
	mov	x21, x0
	mov	x25, x1
	mov	x19, x2
	CSTR	x0, "\"initRange\":"
	bl	within
	cbz	x0, Lfi_rate
	GADDR	x1, Lk_end
	bl	jnum
	str	x0, [x19, #FMT_INIT]
	CSTR	x0, "\"indexRange\":"
	bl	within
	cbz	x0, Lfi_rate
	mov	x20, x0
	GADDR	x1, Lk_start
	bl	jnum
	str	x0, [x19, #FMT_IDX0]
	mov	x0, x20
	GADDR	x1, Lk_end
	bl	jnum
	str	x0, [x19, #FMT_IDX1]
Lfi_rate:
	CSTR	x0, "\"bitrate\":"
	bl	within
	cbz	x0, Lfi_codecs
	add	x0, x0, #10
	bl	strtol10
	str	x0, [x19, #FMT_RATE]
Lfi_codecs:
	CSTR	x0, "codecs=\\\""            ; in the JSON text: codecs=\"...\"
	bl	within
	cbz	x0, Lret4
	add	x20, x0, #9
	mov	x0, x20
	mov	w1, #92                   ; backslash
	bl	_strchr
	cbz	x0, Lret4
	sub	x2, x0, x20
	cmp	x2, #63
	b.hs	Lret4
	add	x0, x19, #FMT_CODECS
	mov	x1, x20
	add	x2, x2, #1
	bl	_strlcpy
	b	Lret4

; parse_player(job, response) — the best AAC stream, then title, channel, length and live flag; w0 = 1 if there is a stream.
	.pushsection __DATA,__data
Lk_itag:	.asciz	"\"itag\":"
	.popsection
parse_player:
	FRAME	4, 48, 1	; the best picture's "url" value and score, its JSON span, the sound's span
	stp	xzr, xzr, [sp]
	stp	xzr, xzr, [sp, #16]
	stp	xzr, xzr, [sp, #32]
	mov	x0, x1
	CSTR	x1, "\"streamingData\":"
	bl	_strstr
	cbz	x0, Lpp_no
	mov	x21, x0
	mov	x22, #0                   ; the best format's "url" value
	mov	w23, #-1                  ; and its score
Lpp_fmt:
	mov	x0, x21
	GADDR	x1, Lk_itag
	bl	jfind
	cbz	x0, Lpp_picked
	mov	x21, x0
	bl	strtol10
	mov	x24, x0
	mov	x0, x21
	GADDR	x1, Lk_itag
	bl	_strstr
	mov	x25, x0                   ; the next format starts here
	cbnz	x0, Lpp_one
	mov	x0, x21                   ; the last one ends where videoDetails starts
	CSTR	x1, "\"videoDetails\":"
	bl	_strstr
	mov	x25, x0
Lpp_one:
	GADDR	x0, Ls_url
	bl	within
	cbz	x0, Lpp_fmt               ; no plain URL (a cipher or SABR)
	add	x26, x0, #6
	CSTR	x0, "mp4a"
	bl	within
	cbz	x0, Lpp_video             ; not AAC: the HLS made here carries AAC
	GADDR	x0, Ls_vmp4
	bl	within
	cbnz	x0, Lpp_fmt
	cmp	x24, #140                 ; score: the original track 8, itag 140 4, audio only 2, no loudness compression 1
	cset	w24, eq
	lsl	w24, w24, #2
	CSTR	x0, "\"audioIsDefault\":true"
	bl	within
	cmp	x0, #0
	cset	w9, ne
	orr	w24, w24, w9, lsl #3
	CSTR	x0, "\"audio/"
	bl	within
	cbz	x0, Lpp_drc
	add	w24, w24, #2
Lpp_drc:
	CSTR	x0, "\"isDrc\":true"
	bl	within
	cbnz	x0, Lpp_score
	add	w24, w24, #1
Lpp_score:
	cmp	w24, w23
	b.le	Lpp_fmt
	mov	w23, w24
	mov	x22, x26
	stp	x21, x25, [sp, #32]
	b	Lpp_fmt
Lpp_video:
	GADDR	x0, Ls_vmp4         ; a picture: MP4, SDR, H.264 (or AV1 where it decodes in hardware)
	bl	within
	cbz	x0, Lpp_fmt
	CSTR	x0, "HDR"
	bl	within
	cbnz	x0, Lpp_fmt
	mov	x24, #0
	CSTR	x0, "avc1"
	bl	within
	cbnz	x0, Lpp_height
	ldr	w9, [x28, #G_AV1]
	cbz	w9, Lpp_fmt
	CSTR	x0, "av01"
	bl	within
	cbz	x0, Lpp_fmt
	mov	x24, #1                   ; AV1: the same picture in fewer bytes
Lpp_height:
	CSTR	x0, "\"height\":"
	bl	within
	cbz	x0, Lpp_fmt
	add	x0, x0, #9
	bl	strtol10
	cmp	x0, #VIDEO_MAX_H
	b.gt	Lpp_fmt
	add	x24, x24, x0, lsl #2      ; score: height, then 60 fps, then the codec
	CSTR	x0, "\"fps\":"
	bl	within
	cbz	x0, Lpp_vscore
	add	x0, x0, #6
	bl	strtol10
	cmp	x0, #30
	cset	x9, gt
	add	x24, x24, x9, lsl #1
Lpp_vscore:
	ldr	x9, [sp, #8]
	cmp	x24, x9
	b.le	Lpp_fmt
	stp	x26, x24, [sp]
	stp	x21, x25, [sp, #16]
	b	Lpp_fmt
Lpp_picked:
	ldp	x0, x1, [sp, #32]
	add	x2, x19, #JOB_AFMT
	cbz	x0, 1f
	bl	fmt_info
1:	ldp	x0, x1, [sp, #16]
	add	x2, x19, #JOB_VFMT
	cbz	x0, 1f
	bl	fmt_info
1:	ldr	x0, [sp]
	ADDO	x1, x19, JOB_VURL
	mov	x2, #4096
	bl	jstr
	mov	x0, x22
	add	x1, x19, #JOB_URL
	mov	x2, #4096
	bl	jstr
	add	x0, x19, #JOB_URL
	CSTR	x1, "http"
	mov	x2, #4
	bl	_strncmp
	cbnz	w0, Lpp_no                ; only a web URL is ever played
	mov	x0, x20
	CSTR	x1, "\"title\":"
	bl	jfind
	add	x1, x19, #(JOB_TRACK + T_TITLE)
	mov	x2, #512
	bl	jstr
	mov	x0, x20
	CSTR	x1, "\"author\":"
	bl	jfind
	add	x1, x19, #(JOB_TRACK + T_ARTIST)
	mov	x2, #256
	bl	jstr
	mov	x0, x20                   ; artwork: the largest thumbnail YouTube lists (they grow along the list)
	CSTR	x1, "\"thumbnails\":["
	bl	jfind
	cbz	x0, Lpp_thumbed
	mov	x21, x0
	mov	w1, #']'
	bl	_strchr
	cbz	x0, Lpp_thumbed
	mov	x25, x0
	mov	x22, #0
Lpp_thumb:
	mov	x0, x21
	GADDR	x1, Ls_url
	bl	_strstr
	cbz	x0, Lpp_tpick
	cmp	x0, x25
	b.hs	Lpp_tpick
	add	x21, x0, #1
	add	x22, x0, #6
	b	Lpp_thumb
Lpp_tpick:
	mov	x0, x22
	add	x1, x19, #(JOB_TRACK + T_ART)
	mov	x2, #2048
	bl	jstr
Lpp_thumbed:
	mov	x0, x20
	CSTR	x1, "\"lengthSeconds\":\""
	bl	jfind
	cbz	x0, Lpp_live
	bl	strtol10
	str	x0, [x19, #JOB_DUR]
Lpp_live:
	mov	x0, x20                   ; YouTube's own HLS, when offered: AirPlay's, and a live broadcast's picture
	CSTR	x1, "\"hlsManifestUrl\":"
	bl	jfind
	ADDO	x1, x19, JOB_HLS
	mov	x2, #4096
	bl	jstr
	mov	x0, x20
	CSTR	x1, "\"isLive\":true"
	bl	_strstr
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x19, #JOB_LIVE]
	cbz	w9, Lpp_yes
	str	xzr, [x19, #JOB_DUR]      ; a live broadcast has no length
	ADDO	x0, x19, JOB_VURL
	ADDO	x1, x19, JOB_HLS
	mov	x2, #4096
	bl	_strlcpy
Lpp_yes:
	mov	w0, #1
	b	Lret4
Lpp_no:
	mov	x0, x20                   ; YouTube's reason, e.g. a bot check
	CSTR	x1, "\"reason\":"
	bl	jfind
	add	x1, x19, #JOB_MSG
	mov	x2, #128
	bl	jstr
	b	Lnil4

; resolve(job) -> PLAY_OK with the job's stream and track filled, or PLAY_FAILED (JOB_ERR says why, when known).
resolve:
	FRAME	4, RS_SIZE
	mov	x20, x0
	bl	_objc_autoreleasePoolPush
	mov	x26, x0
	ldr	x22, [x20, #JOB_QUERY]    ; a file or another site needs no lookup
	ldrb	w9, [x22]
	cmp	w9, #'/'
	b.eq	Lrs_file
	mov	x0, x22
	CSTR	x1, "file://"
	mov	x2, #7
	bl	_strncmp
	cbz	w0, Lrs_file
	mov	x0, x22
	bl	is_link
	cbz	w0, Lrs_tube              ; search words
	mov	x0, x22
	GADDR	x1, Ls_sep
	bl	_strstr
	add	x9, x0, #3
	cmp	x0, #0
	csel	x23, x9, x22, ne
	mov	x0, x23
	GADDR	x1, Ls_qend
	bl	_strcspn
	add	x24, x23, x0
	mov	x0, x23
	CSTR	x1, "youtu"
	CALLF	strcasestr
	cmp	x0, #0
	ccmp	x0, x24, #2, ne
	b.lo	Lrs_tube
	mov	x0, x20                   ; any other address plays as it is
	bl	resolve_web
	b	Lrs_named
Lrs_file:
	mov	x0, x20
	bl	resolve_file
Lrs_named:
	mov	w21, w0
	b	Lrs_pool
Lrs_tube:
	mov	w21, #PLAY_FAILED
	LOCK
	add	x0, sp, #RS_VIS           ; a visitorData first, as the WEB client, once per launch
	BADDR	x1, B_VISITOR
	mov	x2, #288
	bl	_strlcpy
	UNLOCK
	ldrb	w9, [sp, #RS_VIS]
	cbnz	w9, Lrs_id
	ADDR	x0, Lep_guide
	ADDR	x1, Lc_web
	CSTR	x2, "}"
	mov	x3, sp
	bl	api
	cbz	w0, Lrs_id
	ldr	x0, [sp, #RS_BUF]
	CSTR	x1, "\"visitorData\":\""
	bl	jfind                     ; its JSON text goes into our requests as it is
	cbz	x0, Lrs_vfree
	mov	x22, x0
	CSTR	x1, "\""
	bl	_strcspn
	cbz	x0, Lrs_vfree
	stp	x0, x22, [sp]
	add	x0, sp, #RS_VIS
	mov	x1, #288
	CSTR	x2, ",\"visitorData\":\"%.*s\""
	bl	_snprintf
	LOCK
	BADDR	x0, B_VISITOR
	add	x1, sp, #RS_VIS
	mov	x2, #288
	bl	_strlcpy
	UNLOCK
Lrs_vfree:
	ldr	x0, [sp, #RS_BUF]
	bl	_free
Lrs_id:
	ldr	x22, [x20, #JOB_QUERY]
	mov	x0, x22
	bl	is_link
	cbz	w0, Lrs_search
	mov	x0, x22
	add	x1, sp, #RS_ID
	bl	video_id
	mov	x22, x0
	b	Lrs_player
Lrs_search:
	add	x0, sp, #RS_ESC           ; the top video result, as the ANDROID client
	mov	x1, x22
	bl	jesc
	add	x9, sp, #RS_ESC
	str	x9, [sp]
	add	x0, sp, #RS_TAIL
	mov	x1, #1280
	CSTR	x2, ",\"query\":\"%s\",\"params\":\"EgIQAfABAQ==\"}"
	bl	_snprintf
	ADDR	x0, Lep_search
	ADDR	x1, Lc_android
	add	x2, sp, #RS_TAIL
	mov	x3, sp
	bl	api
	cbz	w0, Lrs_done
	ldr	x0, [sp, #RS_BUF]
	CSTR	x1, "\"compactVideoRenderer\":"
	bl	jfind
	CSTR	x1, "\"videoId\":"
	bl	jfind
	add	x1, sp, #RS_ID
	mov	x2, #16
	bl	jstr
	ldr	x0, [sp, #RS_BUF]
	bl	_free
	add	x22, sp, #RS_ID
	ldrb	w9, [x22]
	cbz	w9, Lrs_done              ; no results
Lrs_player:
	add	x0, sp, #RS_ESC
	mov	x1, x22
	bl	jesc
	add	x23, sp, #RS_CPN          ; a random client playback nonce
	mov	w24, #16
Lrs_cpn:
	mov	w0, #64
	CALLF	arc4random_uniform
	CSTR	x9, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
	ldrb	w9, [x9, w0, uxtw]
	strb	w9, [x23], #1
	subs	w24, w24, #1
	b.ne	Lrs_cpn
	strb	wzr, [x23]
	add	x9, sp, #RS_ESC
	add	x10, sp, #RS_CPN
	stp	x9, x10, [sp]
	add	x0, sp, #RS_TAIL
	mov	x1, #1280
	CSTR	x2, ",\"videoId\":\"%s\",\"contentCheckOk\":true,\"racyCheckOk\":true,\"playbackContext\":{\"contentPlaybackContext\":{\"html5Preference\":\"HTML5_PREF_WANTS\"}},\"cpn\":\"%s\"}"
	bl	_snprintf
	ADDR	x23, Lclients
Lrs_client:
	ldrh	w24, [x23]
	cbz	w24, Lrs_none
	ADDR	x0, Lep_player
	add	x1, x23, #2
	add	x2, sp, #RS_TAIL
	mov	x3, sp
	bl	api
	add	x23, x23, x24
	cbz	w0, Lrs_client
	mov	x0, x20
	ldr	x1, [sp, #RS_BUF]
	bl	parse_player
	mov	w25, w0
	ldr	x0, [sp, #RS_BUF]
	bl	_free
	cbz	w25, Lrs_client           ; the next client may cover what this one refused
	ldrb	w9, [x20, #(JOB_TRACK + T_ART)]
	cbnz	w9, Lrs_ok
	str	x22, [sp]                 ; no thumbnail listed: this one always exists
	add	x0, x20, #(JOB_TRACK + T_ART)
	mov	x1, #2048
	CSTR	x2, "https://i.ytimg.com/vi/%s/hqdefault.jpg"
	bl	_snprintf
Lrs_ok:
	mov	w21, #PLAY_OK
	b	Lrs_done
Lrs_none:
	add	x0, x20, #JOB_MSG
	str	x0, [x20, #JOB_ERR]
	ldrb	w9, [x0]
	cbnz	w9, Lrs_done              ; the reason YouTube gave
	str	x22, [sp]
	mov	x1, #128
	CSTR	x2, "no playable formats for %s"
	bl	_snprintf
Lrs_done:
Lrs_pool:
	mov	x0, x26
	bl	_objc_autoreleasePoolPop
	mov	w0, w21
	b	Lret4

; ---- User interface (main thread) ----

; mkstr(cstr) -> an autoreleased NSString.
mkstr:
	mov	x2, x0
	CLASS	x0, NSString
	SENDT	S_stringWithUTF8String_

; setstr(control, cstr) — control.stringValue = cstr.
setstr:
	FRAME	1, 0, 1
	mov	x0, x1
	bl	mkstr
	mov	x2, x0
	mov	x0, x19
	SEND	S_setStringValue_
	b	Lret1

; frame_rect(x0, rect) — d0-d3 = the NSRect of a packed top-left rect; x0 is kept.
frame_rect:
	ubfx	x9, x1, #48, #16
	ubfx	x10, x1, #16, #16
	mov	w11, #WIN_H
	sub	w11, w11, w10
	sub	w11, w11, w9              ; y = WIN_H - top - height
	and	x10, x1, #0xffff
	scvtf	d0, w10
	scvtf	d1, w11
	ubfx	x10, x1, #32, #16
	scvtf	d2, w10
	scvtf	d3, w9
	ret

; ui_run(program) — run a UI program (written with the macros of the Tables, argument kinds in Lk_table, operations in Lop_table).
	.equ VM_INT,	0                 ; x0-x7
	.equ VM_DBL,	64                ; d0-d5
	.equ VM_LOC,	112               ; locals a-h
	.equ VM_F,	176               ; the caller's d8: the programs' double accumulator f
	.equ VM_SIZE,	192
	.equ OP_CALL,	5                 ; operations told apart inside their handlers
	.equ OP_JMP,	14
	.equ OP_IMM,	17
	.equ OP_MSGR,	64
	.equ OP_LDX,	68
	.equ OP_SL,	23
ui_run:
	mov	x9, x0
; vm_run(arguments, program x9) -> x0 = the program's current object at its end; its locals a-h start as x0-x7.
vm_run:
Lvm_base:
	FRAME	4, VM_SIZE
	stp	x0, x1, [sp, #VM_LOC]
	stp	x2, x3, [sp, #(VM_LOC + 16)]
	stp	x4, x5, [sp, #(VM_LOC + 32)]
	stp	x6, x7, [sp, #(VM_LOC + 48)]
	str	d8, [sp, #VM_F]
	mov	x19, x9
Lvm_op:
	ldrb	w9, [x19], #1
	adr	x10, Lop_table
	ldrb	w10, [x10, x9]
	adr	x11, Lop_base
	add	x11, x11, x10, lsl #2
	br	x11
Lop_base:
Lop_end:
	mov	x0, x20
	ldr	d8, [sp, #VM_F]
	b	Lret4
Lop_fls:
	ldrb	w10, [x19], #1            ; f and a local: FL loads, FS stores
	add	x10, sp, x10, lsl #3
	tbnz	w9, #0, 1f
	ldr	d8, [x10, #VM_LOC]
	b	Lvm_op
1:	str	d8, [x10, #VM_LOC]
	b	Lvm_op
Lop_fk:
	ldrh	w10, [x19], #2            ; f = n / 16
	ucvtf	d8, w10, #4
	b	Lvm_op
Lop_fi:
	tbz	w9, #0, 1f                ; FI: f = current; FT: current = f, truncated
	scvtf	d8, x20
	b	Lvm_op
1:	fcvtzs	x20, d8
	b	Lvm_op
Lop_fop:
	ldrb	w11, [x19], #1            ; f = f op a local (FOP) or n / 16 (FOPK)
	tbz	w9, #0, 1f
	ldrb	w10, [x19], #1
	add	x10, sp, x10, lsl #3
	ldr	d1, [x10, #VM_LOC]
	b	2f
1:	ldrh	w10, [x19], #2
	ucvtf	d1, w10, #4
2:	adr	x12, Lfop_base
	add	x12, x12, x11, lsl #3
	br	x12
Lfop_base:
	fadd	d8, d8, d1                ; 0
	b	Lvm_op
	fsub	d8, d8, d1                ; 1
	b	Lvm_op
	fmul	d8, d8, d1                ; 2
	b	Lvm_op
	fdiv	d8, d8, d1                ; 3
	b	Lvm_op
	fmin	d8, d8, d1                ; 4
	b	Lvm_op
	fmax	d8, d8, d1                ; 5
	b	Lvm_op
	fcmp	d8, d1                    ; 6: current = f > it
	b	Lfop_gt
	frintp	d8, d8                    ; 7: up to a whole number
	b	Lvm_op
	frintm	d8, d8                    ; 8: down
	b	Lvm_op
	fabd	d8, d8, d1                ; 9: the distance
	b	Lvm_op
Lfop_gt:
	cset	x20, gt
	b	Lvm_op
Lop_slot:
	ldrb	w10, [x19], #1            ; a G slot
	add	x10, x28, x10, lsl #3
Lop_ls:
	tbz	w9, #0, 1f                ; odd operations store, even ones load
	str	x20, [x10]
	b	Lvm_op
1:	ldr	x20, [x10]
	b	Lvm_op
Lop_field:
	ldrh	w10, [x19], #2            ; a B field
	add	x10, x27, x10
	b	Lop_ls
Lop_wfield:
	ldrh	w10, [x19], #2            ; a B word
	add	x10, x27, x10
	b	Lop_wls
Lop_word:
	ldrb	w10, [x19], #1            ; a G word, at 4 * n
	add	x10, x28, x10, lsl #2
Lop_wls:
	tbz	w9, #0, 1f
	ldr	w20, [x10]
	b	Lvm_op
1:	str	w20, [x10]
	b	Lvm_op
Lop_local:
	sub	w10, w9, #OP_SL           ; a local a-h: store, load, compare, add, subtract
	and	w11, w10, #7
	add	x11, sp, x11, lsl #3
	ldr	x12, [x11, #VM_LOC]
	lsr	w10, w10, #3
	cbnz	w10, 1f
	str	x20, [x11, #VM_LOC]
	b	Lvm_op
1:	cmp	w10, #2
	b.lo	Lop_set
	b.eq	Lop_eq
	cmp	w10, #4
	b.eq	2f
	add	x20, x20, x12
	b	Lvm_op
2:	sub	x20, x20, x12
	b	Lvm_op
Lop_slotc:
	ldrb	w10, [x19], #1            ; compared with a G slot
	ldr	x12, [x28, x10, lsl #3]
Lop_eq:
	cmp	x20, x12
	cset	x20, eq
	b	Lvm_op
Lop_imm:
	ldrsb	x12, [x19], #1            ; a small number: set, add, compare, a bit, a shift
	sub	w10, w9, #OP_IMM
	cbz	w10, Lop_set
	cmp	w10, #2
	b.lo	1f
	b.eq	Lop_eq
	cmp	w10, #4
	b.lo	2f
	b.eq	3f
	lsl	x20, x20, x12
	b	Lvm_op
1:	add	x20, x20, x12
	b	Lvm_op
2:	cmp	x20, x12
	cset	x20, lt
	b	Lvm_op
3:	lsr	x20, x20, x12
	and	x20, x20, #1
	b	Lvm_op
Lop_set:
	mov	x20, x12
	b	Lvm_op
Lop_mem:
	sub	w10, w9, #OP_LDX          ; memory at current or at a local, plus an offset
	cmp	w10, #9
	b.lo	1f
	ldrb	w11, [x19], #1            ; stores: into local n's pointer
	add	x11, sp, x11, lsl #3
	ldr	x11, [x11, #VM_LOC]
1:	ldrh	w12, [x19], #2
	adr	x13, Lmem_base
	add	x13, x13, x10, lsl #3
	br	x13
Lmem_base:
	ldr	x20, [x20, x12]           ; LDX
	b	Lvm_op
	ldr	w20, [x20, x12]           ; LDW
	b	Lvm_op
	ldrb	w20, [x20, x12]           ; LDB
	b	Lvm_op
	add	x20, x20, x12             ; ADDH
	b	Lvm_op
	mul	x20, x20, x12             ; MULH
	b	Lvm_op
	sdiv	x20, x20, x12             ; DIVH
	b	Lvm_op
	and	x20, x20, x12             ; ANDH
	b	Lvm_op
	add	x20, x27, x12             ; LEAB
	b	Lvm_op
	b	Lop_be                    ; LDBE
	nop
	str	x20, [x11, x12]           ; STX
	b	Lvm_op
	str	w20, [x11, x12]           ; STW
	b	Lvm_op
Lop_be:
	ldr	w20, [x20, x12]           ; a big-endian word
	rev	w20, w20
	b	Lvm_op
Lop_jump:
	ldrsb	x10, [x19], #1            ; from the next operation
	cmp	w9, #OP_JMP
	b.eq	1f
	cmp	x20, #0
	cset	w11, ne
	eor	w11, w11, w9              ; JZ is even, JNZ odd
	tbnz	w11, #0, Lvm_op
1:	add	x19, x19, x10
	b	Lvm_op
Lop_add:
	ldr	x0, [x28, #G_CONTENT]
	mov	x2, x20
	SEND	S_addSubview_
	b	Lvm_op
Lop_reg:
	ldrb	w10, [x19], #1            ; an index
	add	x11, x27, #B_REG
	ldr	x24, [x11, x10, lsl #3]   ; a class, or a function
	cmp	w9, #OP_CALL
	b.eq	Lop_call
	mov	x20, x24
	b	Lvm_op
Lop_lea:
	ldrsw	x10, [x19], #4            ; an address here, in bytes from Lvm_base
	adr	x20, Lvm_base
	add	x20, x20, x10
	b	Lvm_op
Lop_native:
	ldrsw	x10, [x19], #4            ; a function here, in bytes from Lvm_base
	adr	x24, Lvm_base
	add	x24, x24, x10
Lop_call:
	mov	x22, #0                   ; its arguments start at x0
	b	Lvm_args
Lop_method:
	ldr	x24, [x27, #F_class_addMethod] ; a method of the current class
	mov	x22, #0
	adr	x21, Lk_method
	b	Lvm_fixed
Lop_item:
	ldr	x20, [x28, #G_T1]         ; an item of the current menu
	ldr	x1, [x27, #S_addItemWithTitle_action_keyEquivalent_]
	adr	x21, Lk_item
	b	Lvm_recv
Lop_msgk:
	adr	x21, Lk_short - 2 * OP_MSGR ; kinds "=", "I", "O" or none
	add	x21, x21, x9, lsl #1
	b	1f
Lop_msg:
	mov	x21, #0
1:	ldrb	w10, [x19], #1
	BADDR	x11, B_SEL
	ldr	x1, [x11, x10, lsl #3]
Lvm_recv:
	stp	x20, x1, [sp, #VM_INT]    ; receiver, selector
	ldr	x24, [x27, #F_objc_msgSend]
	mov	x22, #2
	cbnz	x21, Lvm_fixed
Lvm_args:
	mov	x21, x19                  ; kinds, then their arguments
	mov	x0, x19
	bl	nextstr
	mov	x19, x0
Lvm_fixed:
	ldrb	w26, [x21]                ; '=': the result becomes current
	mov	x23, #0
Lvm_kind:
	ldrb	w9, [x21], #1
	cbz	w9, Lvm_send
	adr	x10, Lk_table - '='
	ldrb	w10, [x10, x9]
	adr	x11, Lk_base
	add	x11, x11, x10, lsl #2
	br	x11
Lk_base:
Lk_skip:
	b	Lvm_kind                  ; '='
Lk_ext:
	ldrb	w10, [x19], #1            ; an extern double
	add	x11, x27, #B_REG
	ldr	x11, [x11, x10, lsl #3]
	ldr	d0, [x11]
	b	Lvm_d
Lk_rect:
	ldr	x1, [x19], #8
	bl	frame_rect
	b	Lk_rect4
Lk_raw:
	ldr	x9, [x19], #8             ; x, y, width, height from the bottom-left
	sxth	w10, w9
	scvtf	d0, w10
	asr	x10, x9, #16
	sxth	w10, w10
	scvtf	d1, w10
	asr	x10, x9, #32
	sxth	w10, w10
	scvtf	d2, w10
	asr	x10, x9, #48
	scvtf	d3, w10
Lk_rect4:
	stp	d0, d1, [sp, #VM_DBL]
	stp	d2, d3, [sp, #(VM_DBL + 16)]
	mov	x23, #4
	b	Lvm_kind
Lk_unit:
	ldrb	w9, [x19], #1             ; a color channel: n / 255
	ucvtf	d0, w9
	mov	w9, #255
	ucvtf	d1, w9
	fdiv	d0, d0, d1
	b	Lvm_d
Lk_dbl:
	ldrh	w9, [x19], #2
	ucvtf	d0, w9
	fmov	d1, #0.25
	fmul	d0, d0, d1
Lvm_d:
	add	x9, sp, #VM_DBL
	str	d0, [x9, x23, lsl #3]
	add	x23, x23, #1
	b	Lvm_kind
Lk_byte:
	ldrb	w0, [x19], #1
	b	Lvm_i
Lk_sbyte:
	ldrsb	x0, [x19], #1
	b	Lvm_i
Lk_half:
	ldrh	w0, [x19], #2
	b	Lvm_i
Lk_mem:
	ldrb	w9, [x19], #1             ; inline bytes: their address
	mov	x0, x19
	add	x19, x19, x9
	b	Lvm_i
Lk_locd:
	ldrb	w9, [x19], #1             ; a local, as a double
	add	x9, sp, x9, lsl #3
	ldr	x9, [x9, #VM_LOC]
	scvtf	d0, x9
	b	Lvm_d
Lk_word:
	ldr	w0, [x19], #4
	b	Lvm_i
Lk_quad:
	add	x19, x19, #7
	and	x19, x19, #~7
	ldr	x0, [x19], #8
	b	Lvm_i
Lk_buf:
	ldrh	w9, [x19], #2
	add	x0, x27, x9
	b	Lvm_i
Lk_field:
	ldrh	w9, [x19], #2             ; a B field's value
	ldr	x0, [x27, x9]
	b	Lvm_i
Lk_code:
	ldrsw	x9, [x19], #4             ; a function here
	adr	x0, Lvm_base
	add	x0, x0, x9
	b	Lvm_i
Lk_ldbl:
	ldrb	w9, [x19], #1             ; a local: a double (Z) or a float (W)
	add	x10, sp, x9, lsl #3
	ldr	d0, [x10, #VM_LOC]
	b	Lvm_d
Lk_lflt:
	ldrb	w9, [x19], #1
	add	x10, sp, x9, lsl #3
	ldr	d0, [x10, #VM_LOC]
	fcvt	s0, d0
	b	Lvm_d
Lk_f:
	fmov	d0, d8                    ; f
	b	Lvm_d
Lk_act:
	ldrb	w9, [x19], #1             ; an action's or method's selector
	BADDR	x10, B_ACT
	ldr	x0, [x10, x9, lsl #3]
	b	Lvm_i
Lk_loc:
	sub	w9, w9, #'a'              ; a local
	add	x9, sp, x9, lsl #3
	ldr	x0, [x9, #VM_LOC]
	b	Lvm_i
Lk_types:
	ldrb	w9, [x19]                 ; a method's types: "" for - (void)action:(id)sender
	cbnz	w9, Lk_cstr
	add	x19, x19, #1
	adr	x0, Lk_action
	b	Lvm_i
Lk_cur:
	mov	x0, x20
	b	Lvm_i
Lk_slot:
	ldrb	w9, [x19], #1
	ldr	x0, [x28, x9, lsl #3]
	b	Lvm_i
Lk_cstr:
	mov	x0, x19
	b	Lvm_s
Lk_str:
	mov	x0, x19
	bl	mkstr
	b	Lvm_s
Lk_sel:
	mov	x0, x19
	bl	_sel_registerName
Lvm_s:
	mov	x25, x0
	mov	x0, x19
	bl	nextstr
	mov	x19, x0
	mov	x0, x25
Lvm_i:
	str	x0, [sp, x22, lsl #3]
	add	x22, x22, #1
	b	Lvm_kind
Lvm_send:
	ldp	x0, x1, [sp, #VM_INT]
	ldp	x2, x3, [sp, #(VM_INT + 16)]
	ldp	x4, x5, [sp, #(VM_INT + 32)]
	ldp	x6, x7, [sp, #(VM_INT + 48)]
	ldp	d0, d1, [sp, #VM_DBL]
	ldp	d2, d3, [sp, #(VM_DBL + 16)]
	ldp	d4, d5, [sp, #(VM_DBL + 32)]
	blr	x24
	cmp	w26, #'='                 ; '=': the result becomes current, '>': its low word, '@': d0 truncated
	csel	x20, x0, x20, eq
	cmp	w26, #'>'
	b.ne	1f
	mov	w20, w0
1:	cmp	w26, #'@'
	b.ne	1f
	fcvtzs	x20, d0
1:	cmp	w26, #'?'                 ; '?': x0 current, x1 into local h; '^': d0-d3 into e-h
	b.ne	1f
	mov	x20, x0
	str	x1, [sp, #(VM_LOC + 56)]
1:	cmp	w26, #'^'
	b.ne	Lvm_op
	stp	d0, d1, [sp, #(VM_LOC + 32)]
	stp	d2, d3, [sp, #(VM_LOC + 48)]
	b	Lvm_op
; Lk_table — the handler of each kind from '=' to 'h', in instructions after Lk_base.
.macro KIND handler
	.byte	(\handler - Lk_base) >> 2
.endm
Lk_table:
	KIND	Lk_skip                   ; =
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_skip
	KIND	Lk_skip                   ; A
	KIND	Lk_buf                    ; B
	KIND	Lk_cstr                   ; C
	KIND	Lk_dbl                    ; D
	KIND	Lk_field                  ; E
	KIND	Lk_ext                    ; F
	KIND	Lk_skip
	KIND	Lk_half                   ; H
	KIND	Lk_byte                   ; I
	KIND	Lk_sbyte                  ; J
	KIND	Lk_unit                   ; K
	KIND	Lk_sel                    ; L
	KIND	Lk_mem                    ; M
	KIND	Lk_raw                    ; N
	KIND	Lk_slot                   ; O
	KIND	Lk_code                   ; P
	KIND	Lk_quad                   ; Q
	KIND	Lk_rect                   ; R
	KIND	Lk_str                    ; S
	KIND	Lk_types                  ; T
	KIND	Lk_locd                   ; U
	KIND	Lk_cur                    ; V
	KIND	Lk_lflt                   ; W
	KIND	Lk_word                   ; X
	KIND	Lk_act                    ; Y
	KIND	Lk_ldbl                   ; Z
	KIND	Lk_f                      ; [
	.rept	5                         ; \ to `
	KIND	Lk_skip
	.endr
	.rept	8                         ; a to h
	KIND	Lk_loc
	.endr
; Lop_table — the handler of each operation, in instructions after Lop_base.
.macro OP handler, n=1
	.rept	\n
	.byte	(\handler - Lop_base) >> 2
	.endr
.endm
Lop_table:
	OP	Lop_end                   ; 0
	OP	Lop_slot, 2               ; 1 STO, 2 LD
	OP	Lop_add                   ; 3 ADDV
	OP	Lop_reg, 2                ; 4 CLS, 5 CALL
	OP	Lop_msg                   ; 6 MSG
	OP	Lop_method                ; 7 METHOD
	OP	Lop_item                  ; 8 ITEM
	OP	Lop_field, 2              ; 9 STE, 10 LDE
	OP	Lop_native                ; 11 NCALL
	OP	Lop_jump, 3               ; 12 JZ, 13 JNZ, 14 JMP
	OP	Lop_word, 2               ; 15 LW, 16 SW
	OP	Lop_imm, 6                ; 17 IMM, 18 ADDI, 19 EQ, 20 LT, 21 BIT, 22 SHL
	OP	Lop_local, 40             ; 23 SL, 31 GL, 39 EQL, 47 ADDL, 55 SUBL, of a-h
	OP	Lop_slotc                 ; 63 EQS
	OP	Lop_msgk, 4               ; 64-67: MSG with kinds "=", "I", "O", none
	OP	Lop_mem, 11               ; 68 LDX, 69 LDW, 70 LDB at current + offset, 71 ADDH, 72 MULH, 73 DIVH, 74 ANDH, 75 LEAB, 76 LDBE, 77 STX, 78 STW into a local + offset
	OP	Lop_wfield, 2             ; 79 LDEW, 80 STEW
	OP	Lop_lea                   ; 81 LEA
	OP	Lop_fls, 2                ; 82 FL, 83 FS
	OP	Lop_fk                    ; 84 FK
	OP	Lop_fi, 2                 ; 85 FI, 86 FT
	OP	Lop_fop, 2                ; 87 FOP, 88 FOPK
Lk_short:	.ascii	"=\0I\0O\0\0\0"
Lk_method:	.asciz	"VYPT"                    ; class_addMethod(class, sel, imp, types)
Lk_item:	.asciz	"=SYS"                      ; addItemWithTitle:action:keyEquivalent:
Lk_action:	.asciz	"v@:@"
	.p2align 2

; ---- Rendering ----

; cache_update(cache, text, cap) — w0 = 1, and copy, if text changed.
cache_update:
	FRAME	2, 0, 1
	mov	x21, x2
	bl	_strcmp
	cbz	w0, Lret2
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	bl	_strlcpy
	mov	w0, #1
	b	Lret2

; show_track(title, artist) — the track in the bar and as the window's title (Window menu, Mission Control), when it changed.
show_track:
	VM	Lp_track
	.pushsection __DATA,__data
Lp_track:
	NCALL	cache_update, "=BaH"
	.short	B_UITITLE, 512
	SL	2
	NCALL	cache_update, "=BbH"
	.short	B_UIARTIST, 256
	ADDL	2
	JZ	Lp_track_end
	LD	G_TITLE
	NCALL	setstr, "Va"
	LD	G_ARTIST
	NCALL	setstr, "Vb"
	CALL	F_strlen, "=b"
	JZ	Lp_track_lone
	LD	G_TITLE
	MSG	S_setFrameOrigin_, "DD"
	.short	16 * 4, (ROW2_C + 1) * 4
	JMP	Lp_track_win
	HERE	Lp_track_lone
	LD	G_TITLE                   ; a lone title sits in the middle of its row
	MSG	S_setFrameOrigin_, "DD"
	.short	16 * 4, (ROW2_C - 9) * 4
	HERE	Lp_track_win
	CALL	F_strlen, "=a"
	JNZ	Lp_track_named
	LD	G_WIN
	MSG	S_setTitle_, "S"
	.asciz	"MIA"
	OP_END
	HERE	Lp_track_named
	NCALL	mkstr, "=a"
	SL	2
	LD	G_WIN
	MSG	S_setTitle_, "c"
	HERE	Lp_track_end
	OP_END
	.popsection

; show_art(url) — load new artwork on the worker queue when the URL changed ("" hides it).
	.equ ART_GEN,	0                 ; request generation
	.equ ART_BUF,	8                 ; {data, len}
	.equ ART_URL,	24                ; the URL, inline
show_art:
	VM	Lp_art
	.pushsection __DATA,__data
Lp_art:
	NCALL	cache_update, "=BaH"
	.short	B_UIART, 2048
	JZ	Lp_art_end
	LD	G_ARTGEN
	ADDI	1
	STO	G_ARTGEN                  ; older downloads become stale
	SL	1
	CALL	F_strlen, "=B"
	.short	B_UIART
	JZ	Lp_art_hide
	ADDI	1
	SL	2                         ; c: the URL's size, with its NUL
	ADDH	ART_URL
	SL	3
	CALL	F_calloc, "=Id"
	.byte	1
	JZ	Lp_art_end
	SL	4
	GL	1
	STX	4, ART_GEN
	GL	4
	ADDH	ART_URL
	SL	5
	CALL	F_memcpy, "fBc"
	.short	B_UIART
	CALL	F_dispatch_async_f, "OeP"
	.byte	G_WORKQ >> 3
	.long	art_fetch - Lvm_base
	OP_END
	HERE	Lp_art_hide
	NCALL	art_show, "II"
	.byte	0, 0
	HERE	Lp_art_end
	OP_END
	.popsection

; art_fetch(job) — download the artwork, then hand it to the main thread.
	VMENTRY	art_fetch, Lp_fetch
	.pushsection __DATA,__data
Lp_fetch:
	CALL	F_objc_autoreleasePoolPush, "="
	SL	1
	GL	0
	ADDH	ART_URL
	NCALL	mkreq, "=V"
	JZ	Lp_fetch_done
	SL	2
	GL	0
	ADDH	ART_BUF
	NCALL	fetch, "cV"
	HERE	Lp_fetch_done
	CALL	F_objc_autoreleasePoolPop, "b"
	NCALL	post_main, "Pa"
	.long	art_apply - Lvm_base
	OP_END
	.popsection

; art_show(image, letterboxed) — show an image on the artwork card at its own shape (nil leaves the empty card), cropping a 4:3 thumbnail's bars.
art_show:
	VM	Lp_ashow
	.pushsection __DATA,__data
Lp_ashow:
	LD	G_ART
	MSG	S_layer, "="
	SL	2
	GL	1
	JNZ	Lp_ashow_cut
	GL	2
	MSG	S_setContentsRect_, "DDDD" ; contentsRect, in unit coordinates
	.short	0, 0, 4, 4
	JMP	Lp_ashow_rect
	HERE	Lp_ashow_cut
	FK	2                         ; skip 12.5% at the top and bottom
	FS	4
	FK	12
	FS	5
	GL	2
	MSG	S_setContentsRect_, "DZDZ"
	.short	0
	.byte	4
	.short	4
	.byte	5
	HERE	Lp_ashow_rect
	GL	2
	MSG	S_setContents_, "a"
	GL	0
	EQ	0
	EQ	0
	SW	G_ARTOK
	FK	16                        ; the card's height / width: square without an image
	GL	0
	JZ	Lp_ashow_asp
	FK	9                         ; 16:9 once the bars are cut
	GL	1
	JNZ	Lp_ashow_asp
	GL	0
	MSG	S_size, "^"
	FL	5
	FOP	3, 4
	HERE	Lp_ashow_asp
	FS	6
	GL	6
	STO	G_ARTASP
	NCALL	layout_stage
	NCALL	stage_update
	OP_END
	.popsection

; art_apply(job) — show the downloaded artwork, or the empty card if it is not an image.
	VMENTRY	art_apply, Lp_aapply
	.pushsection __DATA,__data
Lp_aapply:
	GL	0
	LDX	ART_GEN
	EQS	G_ARTGEN
	JZ	Lp_aapply_free            ; superseded by a newer track
	GL	0
	LDX	ART_BUF
	SL	1
	JZ	Lp_aapply_hide
	GL	0
	LDX	ART_BUF + 8
	SL	2
	CLS	NSData
	MSG	S_dataWithBytes_length_, "=bc"
	SL	1
	CLS	NSImage
	MSG	S_alloc, "="
	MSG	S_initWithData_, "=b"
	SL	1
	JZ	Lp_aapply_hide            ; not an image
	MSG	S_size, "^"
	FL	4
	FOPK	2, 48
	FS	4
	FL	5
	FOPK	2, 64
	FOP	9, 4
	FS	4
	FK	16
	FOP	6, 4                      ; |3w - 4h| < 1: 4:3, a letterboxed 16:9 thumbnail
	SL	2
	NCALL	art_show, "bc"
	GL	1
	MSG	S_release                 ; the layer keeps it
	JMP	Lp_aapply_free
	HERE	Lp_aapply_hide
	NCALL	art_show, "II"
	.byte	0, 0
	HERE	Lp_aapply_free
	GL	0
	LDX	ART_BUF
	CALL	F_free, "V"
	CALL	F_free, "a"
	OP_END
	.popsection

; layout_stage() — between the bar and the title bar: the artwork card as large as fits (at its shape), with the note, the spinner and the link field centered on it.
layout_stage:
	VM	Lp_lstage
	.pushsection __DATA,__data
Lp_lstage:
	LD	G_CONTENT
	MSG	S_bounds, "^"             ; g, h: width and height
	LD	G_ARTASP
	SL	0
	FL	7
	FOPK	1, (STAGE_B + STAGE_T + 32) * 16 ; the room's height, with some air
	FOP	3, 0
	FS	7
	FL	6
	FOPK	1, 96 * 16                ; and width
	FOP	4, 7                      ; the widest card that fits both
	FOPK	4, ART_MAX * 16
	FOPK	5, 64 * 16
	FT
	SL	1
	FOP	2, 0
	FT
	SL	2
	LD	G_ART
	NCALL	center_box, "bcV"
	LD	G_NOTE
	NCALL	center_box, "IIV"
	.byte	96, 96
	LD	G_SPIN
	NCALL	center_box, "IIV"
	.byte	SPIN_S, SPIN_S
	LD	G_URLBOX
	NCALL	center_box, "HHV"
	.short	URL_W, URL_H
	NCALL	pic_layout
	OP_END
	.popsection

; pic_layout — the engine's picture in its view: as large as fits at its shown shape, centered, turned as its track says.
pic_layout:
	VM	Lp_piclay
	.pushsection __DATA,__data
Lp_piclay:
	LD	G_SBLAYER
	SL	0
	JNZ	Lp_pic_made
	OP_END                            ; not made yet
	HERE	Lp_pic_made
	LD	G_SBV
	MSG	S_bounds, "^"             ; g, h: the view's width and height
	LEAB	B_PIC
	SL	1
	LDW	0
	SL	2                         ; c: the turn
	BIT	1
	SL	3                         ; d: a quarter turn: on screen, height by width
	GL	1
	LDW	4
	JZ	Lp_pic_whole
	FI
	FS	4
	GL	1
	LDW	8
	JZ	Lp_pic_whole
	FI
	FS	5
	GL	3
	JZ	Lp_pic_fit
	FL	4
	FS	1
	FL	5
	FS	4
	FL	1
	FS	5
	HERE	Lp_pic_fit
	FL	6                         ; the scale that fits
	FOP	3, 4
	FS	1
	FL	7
	FOP	3, 5
	FOP	4, 1
	FS	1
	FL	4
	FOP	2, 1
	FS	4
	FL	5
	FOP	2, 1
	FS	5
	JMP	Lp_pic_own
	HERE	Lp_pic_whole
	FL	6                         ; no size yet: the whole view
	FS	4
	FL	7
	FS	5
	HERE	Lp_pic_own
	GL	3                         ; its own width and height, before the turn
	JZ	Lp_pic_turn
	FL	4
	FS	1
	FL	5
	FS	4
	FL	1
	FS	5
	HERE	Lp_pic_turn
	GL	2                         ; cos: 1 at 0, -1 at 180
	ADDI	-90
	EQ	90
	SL	1
	GL	2
	EQ	0
	SUBL	1
	FI
	FS	1
	GL	1
	STE	B_AFF
	STE	B_AFF + 24
	IMM	0                         ; sin: 1 at 90, -1 at -90 (the turn's word is not sign-extended)
	SL	1
	GL	3
	JZ	Lp_pic_sin
	GL	2
	EQ	90
	SL	1
	ADDL	1
	ADDI	-1
	SL	1
	HERE	Lp_pic_sin
	GL	1
	FI
	FS	1
	GL	1
	STE	B_AFF + 8
	FK	0
	FOP	1, 1
	FS	1
	GL	1
	STE	B_AFF + 16
	CLS	CATransaction             ; at once
	MSG	S_begin
	CLS	CATransaction
	MSG	S_setDisableActions_, "I"
	.byte	1
	GL	0
	MSG	S_setBounds_, "DDZZ"
	.short	0, 0
	.byte	4, 5
	FL	6
	FOPK	2, 8
	FS	6
	FL	7
	FOPK	2, 8
	FS	7
	GL	0
	MSG	S_setPosition_, "ZZ"
	.byte	6, 7
	GL	0
	MSG	S_setAffineTransform_, "B"
	.short	B_AFF
	CLS	CATransaction
	MSG	S_commit
	OP_END
	.popsection

; center_box(width, height, view) — give a view that size in the middle of the stage.
center_box:
	VM	Lp_cbox
	.pushsection __DATA,__data
Lp_cbox:
	LD	G_CONTENT
	MSG	S_bounds, "^"             ; g, h: the stage's width and height
	GL	0
	FI
	FS	0
	GL	1
	FI
	FS	1
	FL	6
	FOP	1, 0
	FOPK	2, 8
	FOPK	8, 0                      ; whole points: crisp edges
	FS	4
	FL	7
	FOPK	1, (STAGE_B + STAGE_T) * 16
	FOP	1, 1
	FOPK	2, 8
	FOPK	8, 0
	FOPK	0, STAGE_B * 16
	FS	5
	GL	2
	MSG	S_setFrame_, "ZZZZ"
	.byte	4, 5, 0, 1
	OP_END
	.popsection

; stage_update() — what the stage shows: This Mac's picture, else the artwork card while a track plays or loads.
stage_update:
	VM	Lp_stage
	.pushsection __DATA,__data
Lp_stage:
	IMM	0
	SL	0                         ; a: the picture shows
	LW	G_AONLY
	JNZ	Lp_stage_pic
	LW	G_HASVIDEO
	SL	0
	HERE	Lp_stage_pic
	IMM	1                         ; the playing one's picture: the engine's or AVPlayer's
	SL	2
	SL	3
	GL	0
	EQ	0
	SL	4
	LW	G_MODE
	JNZ	Lp_stage_av
	GL	4
	SL	2
	JMP	Lp_stage_hide
	HERE	Lp_stage_av
	GL	4
	SL	3
	HERE	Lp_stage_hide
	LD	G_SBV
	MSG	S_setHidden_, "c"
	LD	G_VIDEO
	MSG	S_setHidden_, "d"
	CALL	F_strlen, "=B"            ; a track, or one on its way
	.short	B_UITITLE
	SL	4
	LW	G_LOADING
	ADDL	4
	SL	4
	GL	0
	JZ	Lp_stage_card
	IMM	0                         ; the card, unless the picture covers it
	SL	4
	HERE	Lp_stage_card
	GL	4
	EQ	0
	SL	5
	LD	G_ART
	MSG	S_setHidden_, "f"
	LW	G_ARTOK                   ; the note, on a card without an image, unless the spinner is there
	ADDL	5
	SL	6
	LW	G_LOADING
	ADDL	6
	EQ	0
	EQ	0
	SL	6
	LD	G_NOTE
	MSG	S_setHidden_, "g"
	GL	0
	JZ	Lp_stage_bar
	LW	G_PPSHOWN
	JNZ	Lp_stage_end              ; a playing picture may keep the bar away
	HERE	Lp_stage_bar
	NCALL	bar_show
	HERE	Lp_stage_end
	OP_END
	.popsection

; bar_show() — bring the control bar back.
bar_show:
	ldr	w9, [x28, #G_BARHID]
	cbz	w9, Lbs_ret
	str	wzr, [x28, #G_BARHID]
	fmov	d0, #1.0
; bar_alpha(alpha) — fade the control bar to an opacity.
bar_alpha:
	FRAME	0, 16
	str	d0, [sp]
	ldr	x0, [x28, #G_BAR]
	SEND	S_animator
	ldr	d0, [sp]
	SEND	S_setAlphaValue_
	b	Lret0
Lbs_ret:
	ret

; render_status() — the status message while it is fresh.
render_status:
	VM	Lp_status
	.pushsection __DATA,__data
Lp_status:
	LW	G_MSGERR
	SL	0
	CALL	F_strlen, "=B"
	.short	B_UIMSG
	JZ	Lp_status_hint
	LD	G_MSGT
	SL	1
	LD	G_TICK
	SUBL	1
	LT	1
	JNZ	Lp_status_show
	CALL	F_bzero, "BI"             ; expired
	.short	B_UIMSG
	.byte	1
	HERE	Lp_status_hint
	IMM	0                         ; hints are not errors
	SL	0
	HERE	Lp_status_show
	LD	G_STATUS
	NCALL	setstr, "VB"
	.short	B_UIMSG
	LD	G_SECOND
	SL	1
	GL	0
	JZ	Lp_status_color
	LD	G_RED
	SL	1
	HERE	Lp_status_color
	LD	G_STATUS
	MSG	S_setTextColor_, "b"
	OP_END
	.popsection



; set_status(message, is_error) — show a message for STATUS_TICKS seconds.
set_status:
	FRAME	1
	mov	w19, w1
	mov	x1, x0
	BADDR	x0, B_UIMSG
	mov	x2, #256
	bl	_strlcpy
	str	w19, [x28, #G_MSGERR]
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #STATUS_TICKS
	str	x9, [x28, #G_MSGT]
	bl	render_status
	b	Lret1

; ui_refresh(playing, position, volume, muted) — render This Mac's state and track.
ui_refresh:
	VM	Lp_refresh
	.pushsection __DATA,__data
Lp_refresh:
	NCALL	show_track, "BB"
	.short	B_LTTRACK, B_LTTRACK + T_ARTIST
	NCALL	show_art, "B"
	.short	B_LTTRACK + T_ART
	LW	G_PPSHOWN
	EQL	0
	JNZ	Lp_refresh_enable
	GL	0
	SW	G_PPSHOWN
	LD	G_IMGPLAY
	SL	4
	GL	0
	JZ	Lp_refresh_pp
	LD	G_IMGPAUSE
	SL	4
	HERE	Lp_refresh_pp
	LD	G_PP
	MSG	S_setImage_, "e"
	HERE	Lp_refresh_enable
	LD	G_LTDUR
	SL	5
	LT	1
	EQ	0                         ; seekable: with a known duration
	SL	4
	LD	G_BACK
	MSG	S_setEnabled_, "e"
	LD	G_FWD
	MSG	S_setEnabled_, "e"
	LD	G_POS
	MSG	S_setEnabled_, "e"
	LW	G_SEEKDRAG
	JNZ	Lp_refresh_volume         ; the user is dragging it
	LD	G_SEEKH
	SL	6
	LD	G_TICK
	SUBL	6
	LT	0
	JNZ	Lp_refresh_volume         ; a seek is still settling
	NCALL	show_time, "bf"
	HERE	Lp_refresh_volume
	LW	G_VOLDRAG
	JNZ	Lp_refresh_mute
	LD	G_VOLH
	SL	6
	LD	G_TICK
	SUBL	6
	LT	0
	JNZ	Lp_refresh_mute           ; a volume change is still settling
	LD	G_VOL
	MSG	S_setDoubleValue_, "U"
	.byte	2
	HERE	Lp_refresh_mute
	LW	G_MUTESHOWN
	EQL	3
	JNZ	Lp_refresh_status
	GL	3
	SW	G_MUTESHOWN
	LD	G_IMGUNMUTED
	SL	4
	GL	3
	JZ	Lp_refresh_img
	LD	G_IMGMUTED
	SL	4
	HERE	Lp_refresh_img
	LD	G_MUTE
	MSG	S_setImage_, "e"
	HERE	Lp_refresh_status
	NCALL	render_status
	NCALL	stage_update
	OP_END
	.popsection

; fmt_time(seconds, out[16], hours) — "m:ss", or "h:mm:ss" from one hour up or when hours is set.
fmt_time:
	FRAME	1, 32
	mov	x19, x1
	cmp	x0, #0
	csel	x0, x0, xzr, gt
	mov	x9, #3600
	udiv	x10, x0, x9
	msub	x11, x10, x9, x0
	mov	x9, #60
	udiv	x12, x11, x9
	msub	x13, x12, x9, x11
	orr	x14, x10, x2
	stp	x10, x12, [sp]
	str	x13, [sp, #16]
	CSTR	x2, "%ld:%02ld:%02ld"
	cbnz	x14, Lft_print
	stp	x12, x13, [sp]
	CSTR	x2, "%ld:%02ld"
Lft_print:
	mov	x0, x19
	mov	x1, #16
	bl	_snprintf
	b	Lret1

; show_time(pos, dur) — position slider, elapsed time and time left.
show_time:
	VMT
	GL	0
	STO	G_SHOWPOS
	IMM	1                         ; the range: the duration, 1 when unknown
	SL	2
	GL	1
	LT	1
	JNZ	Lp_time_range
	GL	1
	SL	2
	HERE	Lp_time_range
	LD	G_POS
	MSG	S_setMaxValue_, "U"
	.byte	2
	LD	G_WIN
	MSG	S_occlusionState, "="
	BIT	1
	JNZ	Lp_time_seen
	OP_END                            ; out of sight: the position and times are not redrawn
	HERE	Lp_time_seen
	GL	0                         ; within the track
	SL	3
	SUBL	1
	LT	0
	JNZ	Lp_time_in
	GL	1
	SL	3
	HERE	Lp_time_in
	GL	1
	LT	1
	JZ	Lp_time_known
	IMM	0
	SL	3
	HERE	Lp_time_known
	LD	G_POS
	MSG	S_setDoubleValue_, "U"
	.byte	3
	LEAB	B_TIMEB
	SL	4
	NCALL	fmt_time, "aeI"
	.byte	0
	GL	0
	LT	1
	JZ	Lp_time_now
	GL	1
	LT	1
	JZ	Lp_time_now
	IMM	0
	STW	4, 0
	HERE	Lp_time_now
	LD	G_CUR
	NCALL	setstr, "Ve"
	IMM	0
	STW	4, 0
	GL	1
	LT	1
	JNZ	Lp_time_left
	IMM	'-'                       ; time left
	STW	4, 0
	GL	1
	SUBL	3
	SL	5
	GL	4
	ADDI	1
	SL	6
	NCALL	fmt_time, "fgI"
	.byte	0
	HERE	Lp_time_left
	LD	G_DUR
	NCALL	setstr, "Ve"
	OP_END
	.p2align 2

; ui_play_done(job) — end loading, report the result, free the job.
	VMENTRY	ui_play_done, Lp_done
	.pushsection __DATA,__data
Lp_done:
	GL	0
	LDW	JOB_GEN
	SL	1
	LW	G_PLAYGEN
	EQL	1
	JZ	Lp_done_free
	IMM	0
	SW	G_LOADING
	GL	0
	LDW	JOB_RESULT
	SL	2
	JNZ	Lp_done_idle
	NCALL	local_play, "a"           ; the engine starts first; the controls follow meanwhile
	HERE	Lp_done_idle
	LD	G_SPIN                    ; the spinner rests
	MSG	S_stopAnimation_, "I"
	.byte	0
	GL	2
	JNZ	Lp_done_failed
	LD	G_FIELD                   ; played: the link field empties
	MSG	S_setStringValue_, "S"
	.asciz	""
	NCALL	set_status, "CI"
	.asciz	""
	.byte	0
	JMP	Lp_done_free
	HERE	Lp_done_failed
	NCALL	fail_status, "a"
	HERE	Lp_done_free
	GL	0
	LDX	JOB_QUERY
	CALL	F_free, "V"
	CALL	F_free, "a"
	NCALL	local_poll
	OP_END
	.popsection

; fail_status(job) — the resolver's reason for a link that did not load, else a plain one, as an error.
fail_status:
	FRAME	0, 272
	ldr	x9, [x0, #JOB_ERR]
	CSTR	x0, "Could not load the link."
	cbz	x9, 1f
	str	x9, [sp]                  ; the resolver's own explanation
	add	x0, sp, #16
	mov	x1, #256
	CSTR	x2, "Could not load: %s"
	bl	_snprintf
	add	x0, sp, #16
1:	mov	w1, #1
	bl	set_status
	b	Lret0

; ---- This Mac: AVPlayer; macOS routes the sound to the chosen output (speakers, Bluetooth, AirPlay) ----

; local_play(job) — play on This Mac with the engine: a file, web media, or a YouTube video's two streams.
local_play:
	VM	Lp_lplay
	.pushsection __DATA,__data
Lp_lplay:
	GL	0
	ADDH	JOB_TRACK
	SL	1
	CALL	F_memcpy, "BbH"
	.short	B_LTTRACK, T_SIZE
	GL	0
	LDX	JOB_DUR
	STO	G_LTDUR
	GL	0
	ADDH	JOB_HLS
	SL	1
	CALL	F_strlcpy, "BbH"          ; YouTube's own HLS, for AirPlay
	.short	B_LTVURL, 4096
	IMM	0
	SW	G_FAILED
	SW	G_HASVIDEO
	SW	G_IDLE                    ; the controls stay a moment on a new track
	NCALL	eng_mode
	GL	0
	LDW	JOB_KIND
	SL	3
	JNZ	Lp_lplay_engine
	CALL	F_strlen, "=B"            ; YouTube: AirPlay takes its HLS, if it gave one
	.short	B_LTVURL
	JZ	Lp_lplay_air
	IMM	3
	HERE	Lp_lplay_air
	STE	B_AIRK
	CALL	F_malloc, "=I"
	.byte	32
	JZ	Lp_lplay_none
	SL	5
	LW	G_PLAYGEN
	STW	5, YT_GEN
	GL	0
	LDW	JOB_LIVE
	STW	5, YT_LIVE
	GL	0
	LDX	JOB_DUR
	MULH	1000
	STX	5, YT_DUR
	IMM	0
	STX	5, YT_V
	GL	0
	ADDH	JOB_VURL
	SL	2
	LDB	0
	JZ	Lp_lplay_audio
	CALL	F_strdup, "=c"
	STX	5, YT_V
	HERE	Lp_lplay_audio
	GL	0
	ADDH	JOB_URL
	SL	2
	CALL	F_strdup, "=c"
	STX	5, YT_A
	NCALL	eng_cmd, "Pf"
	.long	eng_tube - Lvm_base
	NCALL	local_poll
	HERE	Lp_lplay_none
	OP_END
	HERE	Lp_lplay_engine
	GL	0
	LDX	JOB_QUERY
	SL	2
	IMM	1                         ; AirPlay takes the same file or URL
	SL	4
	GL	3
	EQ	KIND_FILE
	JNZ	Lp_lplay_src
	GL	0
	ADDH	JOB_URL
	SL	2
	IMM	2
	SL	4
	HERE	Lp_lplay_src
	GL	4
	STE	B_AIRK
	CALL	F_strlcpy, "=BcH"
	.short	B_LTPATH, 1024
	ADDI	1
	SL	4                         ; the source's size
	ADDI	8
	SL	5
	CALL	F_malloc, "=f"
	JZ	Lp_lplay_end
	SL	5                         ; the request: the generation, then the source
	LW	G_PLAYGEN
	STW	5, 0
	GL	5
	ADDI	8
	SL	6
	CALL	F_strlcpy, "gce"
	GL	3
	EQ	KIND_FILE
	JZ	Lp_lplay_web
	NCALL	eng_cmd, "Pf"
	.long	eng_open - Lvm_base
	JMP	Lp_lplay_poll
	HERE	Lp_lplay_web
	NCALL	eng_cmd, "Pf"
	.long	eng_web - Lvm_base
	HERE	Lp_lplay_poll
	NCALL	local_poll
	HERE	Lp_lplay_end
	OP_END
	.popsection

; eng_mode — the engine plays: AVPlayer lets go.
eng_mode:
	FRAME	0
	str	wzr, [x28, #G_MODE]
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, #0
	SEND	S_replaceCurrentItemWithPlayerItem_
	mov	w9, #1
	str	w9, [x28, #G_PLAYING]
	b	Lret0

; local_poll() — publish This Mac's playback state (its own duration and picture, once known) and re-render.
local_poll:
	FRAME	4, 48                     ; a CMTime at sp + 16
	ldr	w9, [x28, #G_MODE]
	cbz	w9, Llq_engine
	ldr	x19, [x28, #G_PLAYER]
Llq_poll:
	mov	x0, x19
	SEND	S_currentItem
	mov	x24, x0
	mov	w20, #0                   ; playing, or about to
	mov	w25, #0                   ; a picture
	cbz	x0, Llq_time              ; nothing loaded
	SEND	S_status
	cmp	x0, #PLAYER_ITEM_FAILED
	b.ne	Llq_item
	ldr	w9, [x28, #G_FAILED]
	cbnz	w9, Llq_time
	mov	w1, #1
	str	w1, [x28, #G_FAILED]
	CSTR	x0, "Could not play this media."
	bl	set_status
	b	Llq_time
Llq_item:
	ldr	x9, [x28, #G_LTDUR]
	cbnz	x9, Llq_size              ; YouTube said it
	mov	x0, x24
	add	x8, sp, #16
	SEND	S_duration
	ldr	w9, [sp, #28]             ; flags: valid, and not indefinite or infinite
	tbz	w9, #0, Llq_size
	tst	w9, #0x1c
	b.ne	Llq_size
	ldr	x9, [sp, #16]
	ldrsw	x10, [sp, #24]
	sdiv	x9, x9, x10
	str	x9, [x28, #G_LTDUR]
Llq_size:
	mov	x0, x24
	SEND	S_presentationSize        ; d0 = width, 0 without a picture
	fcmp	d0, #0.0
	cset	w25, gt
	mov	x0, x24
	bl	video_tracks
	mov	x0, x19
	SEND	S_timeControlStatus
	cmp	x0, #0
	cset	w20, ne
Llq_time:
	mov	x0, x19
	add	x8, sp, #16               ; a CMTime comes back through x8
	SEND	S_currentTime
	ldr	x9, [sp, #16]             ; value / timescale (0 / 0 with no item gives 0)
	ldrsw	x10, [sp, #24]
	sdiv	x21, x9, x10
Llq_show:
	str	w25, [x28, #G_HASVIDEO]
	bl	air_on
	eor	w2, w0, #1
	ldr	x0, [x28, #G_VOL]
	SEND	S_setEnabled_
	mov	w0, w20
	mov	x1, x21
	ldr	w2, [x28, #G_VOLPCT]
	ldr	w3, [x28, #G_MUTED]
	bl	ui_refresh
	b	Lret4
Llq_engine:
	bl	air_on                    ; AirPlay took the dormant AVPlayer to a TV: it plays on from here
	cbz	w0, 1f
	bl	air_handoff
	ldr	x19, [x28, #G_PLAYER]
	b	Llq_poll
1:	ldr	x9, [x27, #E_VT]          ; the picture's turn and shape, laid out when they change
	cbz	x9, 1f
	ldr	w10, [x9, #TR_ROT]
	ldr	w11, [x9, #TR_DW]
	ldr	w12, [x9, #TR_DH]
	BADDR	x13, B_PIC
	ldp	w14, w15, [x13]
	ldr	w16, [x13, #8]
	cmp	w10, w14
	ccmp	w11, w15, #0, eq
	ccmp	w12, w16, #0, eq
	b.eq	1f
	str	w10, [x13]
	stp	w11, w12, [x13, #4]
	bl	pic_layout
1:	bl	now_ms
	mov	x22, x0                   ; ms
	mov	x11, #1000
	sdiv	x21, x22, x11
	ldr	w20, [x28, #G_PLAYING]
	ldr	x9, [x27, #E_VT]
	cmp	x9, #0
	cset	w25, ne
	ldr	w9, [x27, #E_GEN]
	ldr	w10, [x28, #G_PLAYGEN]
	cmp	w9, w10
	b.ne	Llq_show                  ; still opening
	ldr	x9, [x27, #E_DURMS]
	ldr	x10, [x28, #G_LTDUR]
	udiv	x12, x9, x11
	cmp	x10, #0
	csel	x10, x12, x10, eq         ; the file's own length
	str	x10, [x28, #G_LTDUR]
	cbz	w20, Llq_efail
	cbz	x9, Llq_efail
	subs	x9, x9, x22               ; time left
	b.le	Llq_end
	cmp	x9, #1000
	b.hi	Llq_efail
	scvtf	d0, x9                    ; under a second: poll again right at the end
	ldr	s1, [x28, #G_RATE]
	fcvt	d1, s1
	fdiv	d0, d0, d1
	mov	x9, #16960                ; 1e6 ns per ms
	movk	x9, #15, lsl #16
	scvtf	d1, x9
	fmul	d0, d0, d1
	fcvtzs	x1, d0
	mov	x0, #0
	bl	_dispatch_time
	MAINQ	x1
	mov	x2, #0
	adr	x3, ui_poll
	bl	_dispatch_after_f
	b	Llq_efail
Llq_end:
	str	wzr, [x28, #G_PLAYING]    ; the end: it pauses there
	mov	w20, #0
	adr	x0, eng_rate
	mov	x1, #0
	bl	eng_cmd
Llq_efail:
	ldr	x0, [x27, #E_VR]
	SEND	S_status
	mov	x23, x0
	ldr	x0, [x27, #E_AR]
	SEND	S_status
	cmp	x0, #RENDER_FAILED
	ccmp	x23, #RENDER_FAILED, #4, ne
	b.ne	Llq_show
	ldr	w0, [x28, #G_PLAYGEN]     ; a decoder refused it: AVPlayer tries
	bl	eng_fallback
	b	Lret4

; video_tracks(item) — Audio Only turns the item's picture tracks off (nothing is decoded), and back on.
video_tracks:
	VM	Lp_vtracks
	.pushsection __DATA,__data
Lp_vtracks:
	LW	G_AONLY
	EQ	0
	SL	1                         ; b: on
	GL	0
	MSG	S_tracks, "="
	SL	2
	MSG	S_count, "="
	SL	3
	HERE	Lp_vtracks_next
	GL	3
	ADDI	-1
	SL	3
	LT	0
	JNZ	Lp_vtracks_end
	GL	2
	MSG	S_objectAtIndex_, "=d"
	SL	4
	MSG	S_assetTrack, "="
	MSG	S_mediaType, "="
	MSG	S_isEqualToString_, ">S"
	.asciz	"vide"
	JZ	Lp_vtracks_next
	GL	4
	MSG	S_isEnabled, ">"
	EQL	1
	JNZ	Lp_vtracks_next
	GL	4
	MSG	S_setEnabled_, "b"
	JMP	Lp_vtracks_next
	HERE	Lp_vtracks_end
	OP_END
	.popsection

; local_toggle() — play or pause This Mac.
local_toggle:
	VM	Lp_toggle
	.pushsection __DATA,__data
Lp_toggle:
	LW	G_MODE
	JNZ	Lp_toggle_av
	LW	G_PLAYING
	EQ	0
	SW	G_PLAYING
	JZ	Lp_toggle_rate
	NCALL	now_ms, "="               ; played again at the end: from the start
	SL	0
	LDE	E_DURMS
	JZ	Lp_toggle_rate
	SL	1
	GL	0
	SUBL	1
	LT	0
	JNZ	Lp_toggle_rate
	NCALL	local_seekms, "I"
	.byte	0
	OP_END
	HERE	Lp_toggle_rate
	NCALL	eng_cmd, "PI"
	.long	eng_rate - Lvm_base
	.byte	0
	NCALL	local_poll
	OP_END
	HERE	Lp_toggle_av
	LD	G_PLAYER
	MSG	S_timeControlStatus, "="
	JNZ	Lp_toggle_pause           ; paused: play
	LD	G_PLAYER
	MSG	S_play
	JMP	Lp_toggle_poll
	HERE	Lp_toggle_pause
	LD	G_PLAYER
	MSG	S_pause
	HERE	Lp_toggle_poll
	NCALL	local_poll
	OP_END
	.popsection

; local_seek(seconds) — jump to a position on This Mac.
local_seek:
	mov	x9, #1000
	mul	x0, x0, x9
; local_seekms(ms) — the same, to the millisecond.
local_seekms:
	FRAME	0, 48
	cmp	x0, #0
	csel	x0, x0, xzr, gt
	ldr	w9, [x28, #G_MODE]
	cbnz	w9, Lls_av
	str	x0, [x28, #G_SEEKTO]      ; the engine: seeks queued while one runs collapse into the newest
	add	x9, x28, #G_SEEKPEND
	mov	w10, #1
	swpal	w10, w10, [x9]
	cbnz	w10, Lls_poll
	adr	x0, eng_seekq
	mov	x1, #0
	bl	eng_cmd
Lls_poll:
	bl	local_poll
	b	Lret0
Lls_av:
	mov	x9, #1000                 ; CMTime in milliseconds: value, timescale, flags (valid), epoch
	movk	x9, #1, lsl #32
	stp	x0, x9, [sp]
	str	xzr, [sp, #16]
	mov	x9, #1                    ; zero tolerance: the exact moment, not the segment's start
	movk	x9, #1, lsl #32
	stp	xzr, x9, [sp, #24]
	str	xzr, [sp, #40]
	ldr	x0, [x28, #G_PLAYER]
	mov	x2, sp                    ; passed by reference
	add	x3, sp, #24
	add	x4, sp, #24
	SEND	S_seekToTime_toleranceBefore_toleranceAfter_
	bl	local_poll
	b	Lret0

; local_stop() — pause and rewind This Mac.
local_stop:
	FRAME	0
	str	wzr, [x28, #G_PLAYING]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_pause
	mov	x0, #0
	bl	local_seek
	b	Lret0

; local_setvol(level) — This Mac's volume, 0..100; unmutes.
local_setvol:
	FRAME	1, 0, 1
	bl	air_on
	cbnz	w0, Lret1
	str	w19, [x28, #G_VOLPCT]
	str	wzr, [x28, #G_MUTED]
	bl	vol_apply
	b	Lret1

; local_volstep(delta) — change This Mac's volume by delta, within 0..100.
local_volstep:
	ldr	w9, [x28, #G_VOLPCT]
	add	w0, w9, w0
	cmp	w0, #0
	csel	w0, w0, wzr, gt
	mov	w9, #100
	cmp	w0, w9
	csel	w0, w0, w9, lt
	b	local_setvol

; local_mute() — toggle This Mac's mute.
local_mute:
	ldr	w9, [x28, #G_MUTED]
	eor	w9, w9, #1
	str	w9, [x28, #G_MUTED]
; vol_apply() — both players take G's volume and mute; then the bar shows them.
vol_apply:
	FRAME	0
	ldr	x0, [x28, #G_PLAYER]
	bl	vol_to
	adr	x0, eng_vol
	mov	x1, #0
	bl	eng_cmd
	bl	local_poll
	b	Lret0

; vol_to(player) — an AVPlayer or the sound renderer takes G's volume and mute.
vol_to:
	VMT
	LW	G_VOLPCT
	FI
	FOPK	3, 1600
	FS	1
	GL	0
	MSG	S_setVolume_, "W"
	.byte	1
	LW	G_MUTED
	SL	1
	GL	0
	MSG	S_setMuted_, "b"
	OP_END
	.p2align 2

; air_prepare(self, _cmd, picker) — AirPlay's routes are shown: the dormant AVPlayer gets This Mac's media, paused, so that a picked TV takes it.
	VMENTRY	air_prepare, Lp_air
	.pushsection __DATA,__data
Lp_air:
	LW	G_MODE
	JNZ	Lp_air_end                ; AVPlayer plays it already
	LD	G_PLAYER
	MSG	S_currentItem, "="
	JNZ	Lp_air_end
	LDE	B_AIRK
	SL	3
	JZ	Lp_air_end
	EQ	1
	JZ	Lp_air_url
	NCALL	mkstr, "=B"               ; a file
	.short	B_LTPATH
	SL	4
	CLS	NSURL
	MSG	S_fileURLWithPath_, "=e"
	SL	4
	CLS	AVPlayerItem
	MSG	S_playerItemWithURL_, "=e"
	MSG	S_retain, "="
	JMP	Lp_air_item
	HERE	Lp_air_url
	GL	3
	EQ	2
	JNZ	Lp_air_web
	GL	3
	EQ	3
	JZ	Lp_air_end
	NCALL	make_item, "=B"           ; YouTube's own HLS
	.short	B_LTVURL
	JMP	Lp_air_item
	HERE	Lp_air_web
	NCALL	make_item, "=B"
	.short	B_LTPATH
	HERE	Lp_air_item
	JZ	Lp_air_end
	SL	4                         ; the dormant AVPlayer holds it, silent
	LD	G_PLAYER
	MSG	S_setMuted_, "I"
	.byte	1
	LD	G_PLAYER
	MSG	S_replaceCurrentItemWithPlayerItem_, "e"
	GL	4
	MSG	S_release
	HERE	Lp_air_end
	OP_END
	.popsection

; air_handoff — AirPlay took the dormant AVPlayer: the engine stops, AVPlayer plays on from the engine's moment, at its speed and volume.
air_handoff:
	FRAME	1
	bl	now_ms
	mov	x19, x0
	mov	w9, #1
	str	w9, [x28, #G_MODE]
	adr	x0, eng_close
	mov	x1, #0
	bl	eng_cmd
	bl	vol_apply
	mov	x0, x19
	bl	local_seekms
	ldr	w9, [x28, #G_PLAYING]
	cbz	w9, 1f
	ldr	x0, [x28, #G_PLAYER]
	ldr	s0, [x28, #G_RATE]
	SEND	S_setRate_
1:	bl	stage_update
	b	Lret1

air_on:
	FRAME	0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_currentItem
	cbz	x0, Lret0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_isExternalPlaybackActive
	cbnz	w0, Lret0
	ldr	x0, [x28, #G_PLAYER]
	ldr	x2, [x27, #S__isBufferedAirPlayActive]
	SEND	S_respondsToSelector_
	cbz	w0, Lret0
	ldr	x0, [x28, #G_PLAYER]
	SEND	S__isBufferedAirPlayActive
	b	Lret0

; ---- Network: one NSURLSession; its delegate (the controller) runs on the media queue ----

; mkreq(url) -> an NSMutableURLRequest for a URL string (API_TIMEOUT_MS without data ends it), or nil.
mkreq:
	VM	Lp_mkreq
	.pushsection __DATA,__data
Lp_mkreq:
	NCALL	mkurl, "=a"
	JZ	Lp_mkreq_end
	SL	1
	CLS	NSMutableURLRequest
	MSG	S_requestWithURL_, "=b"
	SL	1
	MSG	S_setTimeoutInterval_, "D"
	.short	API_TIMEOUT_MS / 1000 * 4
	GL	1
	HERE	Lp_mkreq_end
	OP_END
	.popsection

; hdrs(request, pairs) -> the request, with each name and value of a packed list as a header (an empty name ends it); x1 = what follows.
hdrs:
	FRAME	2, 0, 1
Lhs_next:
	ldrb	w9, [x20]
	cbz	w9, Lhs_end
	mov	x0, x20
	bl	nextstr
	mov	x21, x0                   ; the value
	bl	mkstr
	mov	x22, x0
	mov	x0, x20
	bl	mkstr
	mov	x3, x0
	mov	x2, x22
	mov	x0, x19
	SEND	S_setValue_forHTTPHeaderField_
	mov	x0, x21
	bl	nextstr
	mov	x20, x0
	b	Lhs_next
Lhs_end:
	mov	x0, x19
	add	x1, x20, #1
	b	Lret2

; net_start(record) — start its request; the table finds the record from the task's callbacks (media queue).
	ENTRY	net_start
	FRAME	1, 0, 1
	ldr	x0, [x27, #E_SESSION]
	ldr	x2, [x19, #RQ_REQ]
	SEND	S_dataTaskWithRequest_
	cbz	x0, Lns_fail
	mov	x20, x0
	BADDR	x9, B_RQT
	mov	w10, #RQS
1:	ldr	x11, [x9]
	cbz	x11, 2f
	add	x9, x9, #16
	subs	w10, w10, #1
	b.ne	1b
Lns_fail:
	mov	x0, x19                   ; no room or no task: it failed
	mov	w1, #0
	mov	x2, #0
	ldr	x9, [x19, #RQ_DONE]
	blr	x9
	b	Lret1
2:	stp	x20, x19, [x9]
	str	x20, [x19, #RQ_TASK]
	mov	x0, x20
	SEND	S_retain
	SEND	S_resume
	b	Lret1

; rq_find(task) -> its table entry, or 0.
rq_find:
	BADDR	x9, B_RQT
	mov	w10, #RQS
1:	ldr	x11, [x9]
	cmp	x11, x0
	b.eq	2f
	add	x9, x9, #16
	subs	w10, w10, #1
	b.ne	1b
	mov	x9, #0
2:	mov	x0, x9
	ret

; rq_drop(record) — cancel its request, if running; its callbacks find nothing after this.
rq_drop:
	FRAME	1
	ldr	x19, [x0, #RQ_TASK]
	str	xzr, [x0, #RQ_TASK]
	cbz	x19, Lret1
	mov	x0, x19
	bl	rq_find
	cbz	x0, 1f
	stp	xzr, xzr, [x0]
1:	mov	x0, x19
	SEND	S_cancel
	mov	x0, x19
	SEND	S_release
	b	Lret1

; act_netdata(session, task, data) — bytes for a request: sink(record, bytes, length, task).
	ENTRY	act_netdata
	FRAME	2
	mov	x20, x4
	mov	x22, x3
	mov	x0, x3
	bl	rq_find
	cbz	x0, Lret2
	ldr	x19, [x0, #8]
	mov	x0, x20
	SEND	S_bytes
	mov	x21, x0
	mov	x0, x20
	SEND	S_length
	mov	x2, x0
	mov	x1, x21
	mov	x3, x22
	mov	x0, x19
	ldr	x9, [x19, #RQ_SINK]
	blr	x9
	b	Lret2

; act_netdone(session, task, error) — a request ended: ok for a 2xx answer without error.
	ENTRY	act_netdone
	FRAME	2
	mov	x20, x3
	mov	x21, x4
	mov	x0, x3
	bl	rq_find
	cbz	x0, Lret2
	ldr	x19, [x0, #8]
	stp	xzr, xzr, [x0]
	str	xzr, [x19, #RQ_TASK]
	mov	w22, #0
	cbnz	x21, 1f
	mov	x0, x20
	SEND	S_response
	SEND	S_statusCode
	sub	x0, x0, #200
	cmp	x0, #100
	cset	w22, lo
1:	mov	x0, x19
	mov	w1, w22
	mov	x2, x20
	ldr	x9, [x19, #RQ_DONE]
	blr	x9
	mov	x0, x20
	SEND	S_release
	b	Lret2

; sink_buf / done_sync — fetch's body grows in its buffer; its end wakes the waiting thread.
sink_buf:
	add	x3, x0, #RQ_BUF
	mov	x0, x1
	mov	x1, #1
	b	Lbuf_cb
done_sync:
	str	w1, [x0, #RQ_OK]
	ldr	x0, [x0, #RQ_SEM]
	JUMPF	dispatch_semaphore_signal

; fetch(request, buf) — run a request from a worker thread and wait; buf {data, len} gets the body; w0 = 1 for a 2xx answer, buf empty otherwise.
fetch:
	FRAME	1, RQ_SIZE
	mov	x19, x1
	adr	x9, sink_buf
	adr	x10, done_sync
	stp	x9, x10, [sp, #RQ_SINK]
	stp	x0, xzr, [sp, #RQ_REQ]
	stp	xzr, xzr, [sp, #RQ_BUF]
	str	wzr, [sp, #RQ_OK]
	mov	x0, #0
	CALLF	dispatch_semaphore_create
	str	x0, [sp, #RQ_SEM]
	adr	x0, net_start
	mov	x1, sp
	bl	eng_cmd
	ldr	x0, [sp, #RQ_SEM]
	mov	x1, #DISPATCH_TIME_FOREVER
	CALLF	dispatch_semaphore_wait
	ldr	x0, [sp, #RQ_SEM]
	SEND	S_release
	ldr	w20, [sp, #RQ_OK]
	ldp	x0, x9, [sp, #RQ_BUF]
	stp	x0, x9, [x19]
	cbnz	w20, 1f
	bl	_free                     ; a failed answer's body is not kept
	stp	xzr, xzr, [x19]
1:	mov	w0, w20
	b	Lret1

; ---- Streams: media over the network, parsed as it arrives (media queue) ----

; st_pump(stream) — ask for its next bytes, unless a request runs, it ended, or every track it feeds has enough queued.
st_pump:
	FRAME	3, 0, 1
	cbz	x19, Lret3
	ldr	x9, [x19, #ST_URL]
	ldr	x10, [x19, #ST_PLURL]
	orr	x9, x9, x10
	cbz	x9, Lret3
	bl	now_ms
	mov	x20, x0
	ldr	w24, [x19, #ST_FETCH]
	lsr	w15, w24, #1
	mov	w14, #0
	mov	w22, #0
	add	x23, x19, #ST_TR
	mov	w21, #2
Lpu_full:
	ldr	x9, [x23], #8
	cbz	x9, 1f
	ldr	w10, [x28, #G_AONLY]
	ldr	x11, [x27, #E_VT]
	cmp	x11, x9
	ccmp	w10, #0, #4, eq
	b.ne	1f                        ; Audio Only's picture: not waited for
	mov	x0, x9
	bl	ahead_ms
	ldur	x9, [x23, #-8]
	ldp	w10, w11, [x9, #TR_FH]
	sub	w10, w11, w10
	ldr	w11, [x9, #TR_KIND]
	mov	w12, #AHEAD_V
	cmp	w11, #'v'
	mov	w13, #AHEAD_A
	csel	w12, w12, w13, eq
	subs	w16, w11, #'s'
	mov	w13, #AHEAD_S
	csel	w12, w13, w12, eq
	cmp	w10, #(FIFO_N - 16)
	mov	x13, #STALL_FULL
	ccmp	x0, x13, #0, lo
	ccmp	w16, #0, #4, lt
	csinc	w14, w14, wzr, eq
	lsr	w12, w12, w15
	cmp	w10, w12
	csinc	w22, w22, wzr, lo
1:	subs	w21, w21, #1
	b.ne	Lpu_full
	ldr	x9, [x19, #ST_ARCAP]
	tst	x9, #~((ARENA_MAX << 2) - 1)
	bic	w22, w22, w14
	csel	w14, w14, wzr, ne
	str	w14, [x19, #ST_HUNGRY]
	ldr	x9, [x19, #ST_AR]
	cbz	x9, 1f
	mov	x0, x19
	bl	emit
1:	cbz	w24, 2f
	ldr	w10, [x19, #ST_KIND]
	cmp	w10, #1
	b.eq	Lret3
	ldr	x10, [x19, #ST_XLEN]
	cbnz	x10, Lret3
	tbnz	w24, #2, Lret3
	add	w10, w22, #1
	cmp	w24, w10
	b.ne	4f
	cbz	w22, Lret3
	bl	now_ns
	ldr	x9, [x19, #ST_PAUSEAT]
	sub	x0, x0, x9
	lsr	x0, x0, #34
	cbz	x0, Lret3
	mov	w10, #5
	mov	w22, #0
4:	str	w10, [x19, #ST_FETCH]
	ldr	x1, [x27, #S_resume]
	cbz	w22, 3f
	bl	now_ns
	str	x0, [x19, #ST_PAUSEAT]
	adr	x0, Ls_suspend
	bl	_sel_registerName
	mov	x1, x0
3:	ldr	x0, [x19, #(ST_RQ + RQ_TASK)]
	bl	_objc_msgSend
	b	Lret3
Ls_suspend:
	.asciz	"suspend"
	.p2align 2
2:	ldr	w9, [x19, #ST_EOS]
	ldr	w10, [x19, #ST_RETRY]
	orr	w9, w9, w22
	orr	w9, w9, w10
	cbnz	w9, Lret3
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #1
	b.ne	2f
	mov	x0, x19                   ; HLS: its playlist and segments
	bl	hls_pump
	b	Lret3
2:	ldr	w9, [x19, #ST_FRAG]       ; a whole file read so far: nothing past its media data
	ldr	x10, [x19, #ST_MOOV]
	cmp	w9, #0
	ccmp	x10, #0, #4, eq
	b.eq	1f
	ldr	x9, [x19, #ST_POS]
	ldr	x10, [x19, #ST_MDEND]
	cmp	x9, x10
	b.hs	Lpu_end
1:	ldr	x1, [x19, #ST_URL]
	mov	x0, x19
	mov	w2, #0
	ldr	x3, [x19, #ST_POS]
	mov	x4, #0
	bl	st_get
	b	Lret3
Lpu_end:
	mov	x0, x19
	bl	st_end
	b	Lret3

now_ns:
	mov	w0, #CLOCK_UPTIME_RAW
	b	_clock_gettime_nsec_np

; st_end(stream) — no more bytes; if nothing playable came at all, AVPlayer gets the media instead.
st_end:
	ldr	w9, [x0, #ST_XMODE]
	cbnz	w9, xs_nocues             ; the Cues' request: the seek goes on without them
	mov	w9, #1
	str	w9, [x0, #ST_EOS]
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cbnz	x9, 1f
	ldr	w1, [x27, #E_GEN]
	adr	x0, eng_fallback
	b	post_main
1:	ret

; st_sink(record, bytes, length, task) — a request's bytes go to the parser; an answer that is not a success is dropped.
st_sink:
	FRAME	2
	sub	x19, x0, #ST_RQ
	mov	x20, x1
	mov	x21, x2
	mov	x22, x3
	ldr	w9, [x19, #ST_FETCH]
	and	w9, w9, #3
	str	w9, [x19, #ST_FETCH]
	ldr	w9, [x19, #ST_ANS]
	cbnz	w9, 1f
	mov	w9, #1
	str	w9, [x19, #ST_ANS]
	mov	x0, x3
	SEND	S_response
	SEND	S_statusCode
	sub	x9, x0, #200
	cmp	x9, #100
	b.hs	Lsn_bad
	cmp	x0, #206                  ; a range: the stream's whole length from it
	b.ne	2f
	mov	x0, x19
	mov	x1, x22
	bl	st_total
	b	1f
2:	cmp	x0, #200
	b.ne	1f
	ldr	x9, [x19, #ST_POS]        ; the whole stream instead of the range: what lies before the position is dropped
	ldr	x10, [x19, #ST_SKIP]
	add	x9, x9, x10
	str	x9, [x19, #ST_SKIP]
1:	ldr	w9, [x19, #ST_ANS]
	tbnz	w9, #1, Lret2             ; refused
	ldr	x9, [x19, #ST_SKIP]
	cmp	x9, x21
	csel	x10, x9, x21, lo
	sub	x9, x9, x10
	str	x9, [x19, #ST_SKIP]
	add	x20, x20, x10
	subs	x21, x21, x10
	b.eq	Lret2
	ldr	x9, [x19, #ST_GOT]
	add	x9, x9, x21
	str	x9, [x19, #ST_GOT]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	ldr	w9, [x19, #ST_REQT]
	cbz	w9, Lsn_bytes
	cmp	w9, #3
	b.hi	Lsn_parse                 ; an init segment: boxes
	b.lo	Lsn_text                  ; a playlist or key
	ldr	w9, [x19, #ST_ENC]
	cbnz	w9, Lsn_text              ; encrypted: decrypted whole
	bl	seg_bytes
	b	Lsn_pump
Lsn_bytes:
	ldr	w9, [x19, #ST_KIND]
	ldr	x10, [x19, #ST_SPOS]
	orr	x9, x9, x10
	cmp	x21, #7
	ccmp	x9, #0, #0, hs
	b.ne	Lsn_parse                 ; not a stream's first bytes
	ldr	w9, [x20]
	ldur	w10, [x20, #3]
	TYPE	w11, '#','E','X','T'
	TYPE	w12, 'T','M','3','U'
	cmp	w9, w11
	ccmp	w10, w12, #0, eq
	b.ne	Lsn_box
	mov	w9, #1                    ; an HLS playlist: the stream reads its segments instead
	str	w9, [x19, #ST_KIND]
	str	w9, [x19, #ST_REQT]
	ldr	x0, [x19, #ST_URL]
	bl	_strdup
	str	x0, [x19, #ST_PLURL]
	ldr	x0, [x19, #ST_URL]
	bl	_strdup
	str	x0, [x19, #ST_RQURL]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
Lsn_text:
	bl	txt_add
	b	Lret2
Lsn_box:
	ldr	w9, [x20]                 ; Matroska (3) and FLV (4): read by their own cursors
	MOVL	w10, 0xA3DF451A
	mov	w11, #3
	cmp	w9, w10
	b.eq	3f
	and	w9, w9, #0xffffff
	MOVL	w10, 0x564c46
	mov	w11, #4
	cmp	w9, w10
	b.ne	4f
3:	str	w11, [x19, #ST_KIND]
	b	Lsn_parse
4:	ldr	w9, [x20, #4]             ; a box's type is four printable bytes; anything else is sound for AudioFileStream
	mov	w10, #4
1:	and	w11, w9, #0xff
	sub	w11, w11, #0x20
	cmp	w11, #0x5f
	b.hs	2f
	lsr	w9, w9, #8
	subs	w10, w10, #1
	b.ne	1b
	b	Lsn_parse
2:	bl	afs_stream
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
Lsn_parse:
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #2
	b.hs	2f
	bl	st_parse
	b	Lsn_pump
2:	bl	xs_sink
Lsn_pump:
	mov	x0, x19
	bl	st_trim
	b	Lret2
Lsn_bad:
	mov	w9, #3
	str	w9, [x19, #ST_ANS]
	b	Lret2

; st_done(record, ok, task) — a request ended: on to the next bytes, a retry, or the stream's end.
st_done:
	FRAME	2
	sub	x19, x0, #ST_RQ
	mov	w20, w1
	mov	x21, x2
	str	wzr, [x19, #ST_FETCH]
	ldr	w9, [x19, #ST_REQT]
	ldr	x10, [x19, #ST_TXTN]
	cmp	w9, #3
	ccmp	x10, #0, #0, eq
	b.ne	6f
	ldr	x9, [x19, #ST_GOT]
	cbz	x9, 8f
	str	wzr, [x19, #ST_ERRS]
8:	ldr	x10, [x19, #ST_SEGOFF]
	add	x9, x9, x10
	str	x9, [x19, #ST_GOT]
	cmp	w20, #0
	csel	x9, x9, xzr, eq
	str	x9, [x19, #ST_SEGOFF]
6:
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #1
	b.ne	1f
	mov	x0, x19                   ; HLS
	mov	w1, w20
	bl	hls_done
	b	Lret2
1:
	ldp	x9, x10, [x19, #ST_POS]   ; ST_POS, and the parsed position
	ldr	x11, [x19, #ST_GOT]
	add	x9, x9, x11
	str	x9, [x19, #ST_POS]
	cbz	x11, 7f
	str	wzr, [x19, #ST_ERRS]
7:	cbz	w20, Lsd_fail
	cbz	x11, Lsd_end              ; nothing more
	ldr	x10, [x19, #ST_XLEN]
	cmp	x10, #0
	ccmp	x9, x10, #0, ne
	b.hs	Lsd_end
	mov	x0, x21
	SEND	S_response
	SEND	S_statusCode
	cmp	x0, #206
	b.ne	Lsd_end                   ; not a range: the whole stream came
	mov	x0, x21                   ; the CDN's redirect: later requests go straight there
	SEND	S_response
	SEND	S_URL
	SEND	S_absoluteString
	SEND	S_UTF8String
	cbz	x0, Lsd_pump
	mov	x20, x0
	ldr	x1, [x19, #ST_URL]
	bl	_strcmp
	cbz	w0, Lsd_pump
	mov	x0, x20
	bl	_strdup
	cbz	x0, Lsd_pump
	mov	x20, x0
	ldr	x0, [x19, #ST_URL]
	bl	_free
	str	x20, [x19, #ST_URL]
Lsd_pump:
	mov	x0, x19
	bl	st_pump
	b	Lret2
Lsd_fail:
	mov	x0, x21
	SEND	S_response
	SEND	S_statusCode
	sub	x0, x0, #400
	cmp	x0, #100
	b.lo	Lsd_end                   ; refused (e.g. 416 past the end): no retry
	ldr	w9, [x19, #ST_ERRS]
	add	w9, w9, #1
	str	w9, [x19, #ST_ERRS]
	cmp	w9, #NET_TRIES
	b.hs	Lsd_end
	mov	w0, #(RETRY_NS / 500000)
	mov	x1, x19
	bl	st_later
	b	Lret2
Lsd_end:
	mov	x0, x19
	bl	st_end
	b	Lret2

; st_retry(stream) — the next attempt, unless the stream was reset since.
	ENTRY	st_retry
	ldr	w9, [x0, #ST_RETRY]
	cbz	w9, 1f
	str	wzr, [x0, #ST_RETRY]
	b	st_pump
1:	ret

; st_reset(stream) — stop its request and parsing; what it fed stays queued.
st_reset:
	FRAME	1, 0, 1
	add	x0, x19, #ST_RQ
	bl	rq_drop
	ldr	x0, [x19, #ST_BBUF]
	bl	_free
	ldr	x0, [x19, #ST_ARBB]
	cbz	x0, 1f
	bl	_CFRelease                ; the arena goes with its last sample
1:	stp	xzr, xzr, [x19, #ST_BBUF]
	stp	xzr, xzr, [x19, #ST_AR]
	stp	xzr, xzr, [x19, #ST_ARPOS]
	str	xzr, [x19, #ST_ARCAP]
	stp	wzr, wzr, [x19, #ST_PST]
	stp	wzr, wzr, [x19, #ST_FETCH]
	str	wzr, [x19, #ST_ERRS]
	str	wzr, [x19, #ST_RETRY]
	str	xzr, [x19, #ST_SEGOFF]
	b	Lret1

st_trim:
	ldr	x9, [x0, #ST_ARCAP]
	ldr	w10, [x0, #ST_KIND]
	tst	x9, #~((ARENA_MAX << 3) - 1)
	ccmp	w10, #1, #4, ne
	b.eq	st_pump
	ldr	w11, [x0, #ST_PST]
	cmp	w10, #0
	ccmp	w11, #2, #4, eq
	b.ne	st_pump
	FRAME	3, 0, 1
	bl	st_keep
	cbz	x0, Lsk_hgo
	ldr	x9, [x19, #ST_SPOS]
	cmp	x0, x9
	csel	x20, x0, x9, lo
	mov	x0, x19
	bl	st_reset
	mov	x0, x20
	b	Lsk_rew

; st_seek(stream, ms) — its tracks drop what is queued and start again at the sync sample before that moment; a stream without its index yet starts over and seeks once it has it.
st_seek:
	FRAME	3, 0, 1
	bl	st_reset
	str	x20, [x19, #ST_PEND]
	add	x21, x19, #ST_TR          ; each track: its target, nothing queued
	mov	w22, #2
Lsk_tr:
	ldr	x0, [x21], #8
	cbz	x0, 1f
	mov	x1, x20
	bl	trk_target
1:	subs	w22, w22, #1
	b.ne	Lsk_tr
	ldr	w9, [x19, #ST_KIND]
	cmp	w9, #2
	b.eq	Lsk_afs
	b.hi	Lsk_x
	cbnz	w9, Lsk_hls
	ldr	x9, [x19, #ST_MOOV]
	cbz	x9, Lsk_top
	ldr	w9, [x19, #ST_FRAG]
	cbz	w9, Lsk_whole
	ldr	x0, [x19, #ST_SIDX]
	cbz	x0, Lsk_top
	mov	x1, x20
	bl	sidx_find                 ; x0 = the fragment's offset from the anchor
	ldr	x9, [x19, #ST_SIDXEND]
	add	x0, x0, x9
	b	Lsk_at
Lsk_whole:
	mov	x0, x19                   ; a whole file: the cursors find the samples, the stream reads from the earliest
	bl	st_cursors
Lsk_rew:
	ldr	x9, [x19, #ST_MDEND]
	subs	x9, x9, x0
	str	x9, [x19, #ST_LEFT]
	mov	w9, #2
	csel	w9, w9, wzr, ne
	str	w9, [x19, #ST_PST]
	b	Lsk_go
Lsk_hls:
	stp	xzr, xzr, [x19, #ST_SEQ]  ; HLS: the segment from the playlist, or when it comes
	mov	x0, x19
	bl	seg_reset
	str	xzr, [x19, #ST_T0]
	ldr	x9, [x19, #ST_PL]
	cbz	x9, Lsk_hgo
	ldr	w10, [x19, #ST_ENDED]
	cbz	w10, Lsk_stale
	mov	x0, x19
	mov	w1, #1
	mov	x2, x20
	sub	sp, sp, #SG_SIZE
	mov	x3, sp
	bl	seg_scan
	ldp	x9, x10, [sp, #SG_SEQ]
	ldr	w11, [sp, #SG_N]
	add	x10, x10, w11, uxtw
	add	sp, sp, #SG_SIZE
	cmp	w0, #0
	csel	x9, x9, x10, ne           ; past the end: after the last
	str	x9, [x19, #ST_SEQ]
Lsk_hgo:
	str	wzr, [x19, #ST_EOS]
	b	Lhd_next
Lsk_stale:
	mov	w9, #1
	str	w9, [x19, #ST_STALE]
	b	Lsk_hgo
Lsk_afs:
	ldr	x0, [x19, #ST_TR]         ; sound: from AudioFileStream's byte for the moment
	cbz	x0, Lsk_top
	mov	x21, x19
	mov	x19, x0
	mov	x0, x20
	bl	afs_seek
	ldr	x0, [x19, #TR_OFF]
	mov	x19, x21
	b	Lsk_at
Lsk_top:
	mov	x0, #0
Lsk_at:
	str	wzr, [x19, #ST_PST]
Lsk_go:
	stp	x0, x0, [x19, #ST_POS]
	str	xzr, [x19, #ST_EOS]
	b	Lhd_next
Lsk_x:
	ldr	w9, [x19, #ST_XHEAD]
	cbz	w9, Lsk_top               ; Matroska, FLV: the header first, its tracks then at the target
	ldr	x9, [x19, #ST_XCUEP]
	cbz	x9, 1f
	mov	w10, #1
	str	w10, [x19, #ST_XMODE]
	str	xzr, [x19, #ST_XIDXN]
	mov	x0, x9
	b	Lsk_at
1:	str	wzr, [x19, #ST_EOS]       ; the tracks' cursors, waiting for the bytes it reads again: from the earliest
	mov	x0, x19
	bl	xs_cursors
	b	Lsk_at

; trk_target(track, ms) — the track restarts at that moment: queue emptied, earlier samples decoded only.
trk_target:
	FRAME	1, 0, 1
	mov	x9, #-1
	str	x9, [x19, #TR_APTS]       ; packed sound times itself again
	str	xzr, [x19, #TR_LAST]
	bl	trk_tgt
	bl	q_clear
	b	Lret1

; st_cursors(stream) -> x0 = where the stream reads from: each whole-file track at the sync sample before its target, the earliest of them.
st_cursors:
	FRAME	2
	add	x20, x0, #(ST_TR + 16)
	add	x22, x0, #ST_TR
	mov	x21, #0x7fffffffffffffff
1:	ldr	x19, [x22], #8
	cbz	x19, 2f
	bl	trk_seek
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, x21
	csel	x21, x9, x21, lo
2:	cmp	x22, x20
	b.ne	1b
	mov	x0, x21
	b	Lret2

; trk_seek — the cursor at the sync sample before the track's target (preroll for sound) (x19 = track).
trk_seek:
	FRAME	0
	ldp	x9, x0, [x19, #TR_SHIFT]
	add	x0, x0, x9                ; in the media's own time
	ldr	w9, [x19, #TR_KIND]
	mov	w1, #1
	cmp	w9, #'a'
	b.ne	1f
	mov	w1, #(1 + AUDIO_PREROLL)
1:	bl	cur_seek
	b	Lret0

; sidx_find(sidx, ms) -> x0 = the byte offset, from the index's anchor, of the fragment holding that moment.
sidx_find:
	ldrb	w9, [x0]                  ; version: 32- or 64-bit times and offset
	ldr	w10, [x0, #8]
	rev	w10, w10                  ; timescale
	add	x11, x0, #20
	ldr	w12, [x0, #16]
	rev	w12, w12                  ; first offset
	cbz	w9, 1f
	ldr	x12, [x0, #20]
	rev	x12, x12
	add	x11, x0, #28
1:	ldrh	w13, [x11, #2]
	rev16	w13, w13                  ; references
	add	x11, x11, #4
	mul	x1, x1, x10
	mov	x9, #1000
	udiv	x1, x1, x9                ; the moment, in the index's units
	mov	x0, x12
	mov	x14, #0                   ; time so far
2:	cbz	w13, 3f
	ldp	w9, w10, [x11], #12
	rev	w10, w10                  ; duration
	add	x15, x14, x10
	cmp	x15, x1
	b.hi	3f                        ; this one holds it
	rev	w9, w9
	and	w9, w9, #0x7fffffff
	add	x0, x0, x9
	mov	x14, x15
	sub	w13, w13, #1
	b	2b
3:	ret

; st_parse(stream, bytes, length) — boxes as they come: small ones collected and read, media data into arenas, the rest skipped.
st_parse:
	FRAME	3, 0, 1
	mov	x21, x2
Lsp_loop:
	cbz	x21, Lret3
	ldr	w9, [x19, #ST_PST]
	cbz	w9, Lsp_head
	ldr	x22, [x19, #ST_LEFT]      ; bytes for this box in hand
	cmp	x22, x21
	csel	x22, x22, x21, lo
	cmp	w9, #2
	b.eq	Lsp_media
	b.hi	Lsp_skip
	ldp	x0, x9, [x19, #ST_BBUF]   ; 1: collected
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	x9, [x19, #ST_BN]
	add	x9, x9, x22
	str	x9, [x19, #ST_BN]
	bl	Lsp_eat
	cbnz	x9, Lsp_loop
	mov	x0, x19
	bl	box_done
	cbz	w0, Lsp_loop
	b	Lret3                     ; the stream moved: the rest of these bytes is not wanted
Lsp_skip:
	bl	Lsp_eat
	cbnz	x9, Lsp_loop
	str	wzr, [x19, #ST_PST]       ; skipped
	b	Lsp_loop
Lsp_media:
	ldr	x9, [x19, #ST_SPOS]
	ldr	x12, [x19, #ST_ARPOS]
	ldr	x10, [x19, #ST_ARCAP]
	sub	x9, x9, x12
	cmp	x9, x10
	b.lo	2f
	mov	x0, x19                   ; a new arena, from the earliest sample not yet given
	bl	arena_new
	cbz	x0, Lsp_dead
	ldp	x9, x10, [x19, #ST_ARN]
2:	str	x9, [x19, #ST_ARN]
	sub	x10, x10, x9              ; room
	cmp	x22, x10
	csel	x22, x22, x10, lo
	bl	ar_put
	bl	Lsp_eat
	mov	x0, x19
	bl	emit
	ldr	x9, [x19, #ST_LEFT]
	cbnz	x9, Lsp_loop
	str	wzr, [x19, #ST_PST]       ; the media data ended
	b	Lsp_loop
Lsp_dead:
	mov	x0, x19                   ; no memory: this stream stops
	bl	st_reset
	mov	w9, #1
	str	w9, [x19, #ST_EOS]
	b	Lret3
Lsp_head:
	ldr	w9, [x19, #ST_HN]
	mov	w10, #8                   ; size and type, then a 64-bit size if size is 1
	cmp	w9, #8
	b.lo	1f
	mov	w10, #16
1:	sub	w22, w10, w9
	cmp	x22, x21
	csel	x22, x22, x21, lo
	add	x0, x19, #ST_HB
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	w9, [x19, #ST_HN]
	add	w9, w9, w22
	str	w9, [x19, #ST_HN]
	add	x20, x20, x22
	sub	x21, x21, x22
	ldr	x10, [x19, #ST_SPOS]
	add	x10, x10, x22
	str	x10, [x19, #ST_SPOS]
	cmp	w9, #8
	b.lo	Lsp_loop
	ldr	w10, [x19, #ST_HB]
	rev	w10, w10                  ; size
	mov	w11, #8
	cmp	w10, #1
	b.ne	2f
	cmp	w9, #16
	b.lo	Lsp_loop
	ldr	x10, [x19, #(ST_HB + 8)]
	rev	x10, x10
	mov	w11, #16
2:	str	wzr, [x19, #ST_HN]
	ldr	x12, [x19, #ST_SPOS]
	sub	x13, x12, x11
	str	x13, [x19, #ST_BOXPOS]
	cbnz	x10, 3f
	ldr	x10, [x19, #ST_LEN]       ; 0: to the end of the stream
	sub	x10, x10, x13
3:	subs	x10, x10, x11             ; the body
	b.lo	Lsp_bad
	str	x10, [x19, #ST_LEFT]
	ldr	w14, [x19, #(ST_HB + 4)]
	str	w14, [x19, #ST_BOXT]
	mov	w9, #3                    ; skipped, unless known
	TYPE	w15, 'm','d','a','t'
	cmp	w14, w15
	b.eq	Lsp_mdat
	TYPE	w15, 'm','o','o','v'
	cmp	w14, w15
	b.eq	Lsp_keep
	TYPE	w15, 'm','o','o','f'
	cmp	w14, w15
	b.eq	Lsp_keep
	TYPE	w15, 's','i','d','x'
	cmp	w14, w15
	b.ne	Lsp_state
Lsp_keep:
	mov	x15, #BOX_MAX
	cmp	x10, x15
	b.hi	Lsp_state
	ldr	x0, [x19, #ST_BBUF]
	mov	x1, x10
	bl	_realloc
	cbz	x0, Lsp_dead
	stp	x0, xzr, [x19, #ST_BBUF]
	mov	w9, #1
	ldr	x10, [x19, #ST_LEFT]
	cbnz	x10, Lsp_state
	str	wzr, [x19, #ST_PST]       ; an empty box: read now
	mov	x0, x19
	bl	box_done
	cbz	w0, Lsp_loop
	b	Lret3
Lsp_mdat:
	ldr	x9, [x19, #ST_MOOV]
	cbnz	x9, 4f
	ldp	x9, x10, [x19, #ST_SPOS]  ; media data before the movie box: read the movie box after it first
	add	x9, x9, x10
	str	x9, [x19, #ST_MDEND]
	mov	x0, x19
	bl	st_reset
	ldr	x9, [x19, #ST_MDEND]
	stp	x9, x9, [x19, #ST_POS]
	b	Lhd_next
4:	ldr	x9, [x19, #ST_SPOS]
	add	x10, x9, x10
	str	x10, [x19, #ST_MDEND]
	mov	w9, #2
Lsp_state:
	ldr	x10, [x19, #ST_LEFT]
	cmp	x10, #0
	csel	w9, wzr, w9, eq           ; an empty box: nothing to read
	str	w9, [x19, #ST_PST]
	b	Lsp_loop
Lsp_bad:
	mov	x0, x19                   ; not boxes: the stream ends
	bl	st_end
	b	Lret3
; Lsp_eat — x22 bytes of the box consumed; x9 = what is left of it.
Lsp_eat:
	add	x20, x20, x22
	sub	x21, x21, x22
	ldr	x9, [x19, #ST_SPOS]
	add	x9, x9, x22
	str	x9, [x19, #ST_SPOS]
	ldr	x9, [x19, #ST_LEFT]
	sub	x9, x9, x22
	str	x9, [x19, #ST_LEFT]
	ret

; arena_new(stream) -> x0 = 1 with a new arena for the media data, carrying over the bytes of the earliest sample not given yet; 0 without memory.
arena_new:
	FRAME	3, 16, 1
	bl	st_keep                   ; x0 = the stream position still needed
	ldp	x9, x10, [x19, #ST_ARPOS]
	add	x10, x9, x10              ; the old arena's end
	ldr	x11, [x19, #ST_AR]
	ldr	x12, [x19, #ST_SPOS]
	cmp	x11, #0
	ccmp	x10, x12, #2, ne          ; its bytes carry over only if the new ones follow them
	b.hi	1f
	cmp	x0, x9
	csel	x0, x0, x9, hs
	cmp	x0, x10
	b.lo	2f
1:	mov	x0, x12                   ; else from here
	mov	x10, x0
2:	mov	x20, x0
	sub	x21, x10, x0              ; bytes carried over
	sub	x24, x12, x0
	ldr	x9, [x19, #ST_LEFT]
	mov	x10, #ARENA_MAX
	cmp	x9, x10
	csel	x9, x9, x10, lo
	cmp	x9, x24
	csel	x9, x9, x24, hs
	add	x22, x9, x24
	mov	x0, x22
	bl	_malloc
	cbz	x0, Lan_fail
	mov	x23, x0
	cbz	x21, 3f
	ldr	x1, [x19, #ST_AR]
	ldr	x9, [x19, #ST_ARPOS]
	sub	x9, x20, x9
	add	x1, x1, x9
	mov	x2, x21
	bl	_memcpy
3:	ldr	x0, [x19, #ST_ARBB]
	cbz	x0, 4f
	bl	_CFRelease                ; the old arena goes with its last sample
4:	add	x9, x19, #ST_ARBB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x23
	mov	x2, x22
	mov	x3, #0                    ; the default allocator frees it
	mov	x4, #0
	mov	x5, #0
	mov	x6, x22
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Lan_free
	str	x23, [x19, #ST_AR]
	stp	x20, x24, [x19, #ST_ARPOS]
	str	x22, [x19, #ST_ARCAP]
	mov	x0, #1
	b	Lret3
Lan_free:
	mov	x0, x23
	bl	_free
	stp	xzr, xzr, [x19, #ST_AR]
Lan_fail:
	mov	x0, #0
	b	Lret3

ar_put:
	ldr	x9, [x19, #ST_ARN]
	add	x10, x9, x22
	str	x10, [x19, #ST_ARN]
	ldr	x0, [x19, #ST_AR]
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	b	_memcpy

; st_keep -> x0 = the stream position of the earliest sample its tracks have not given yet (x19 = stream).
st_keep:
	ldr	w9, [x19, #ST_KIND]
	ldr	w10, [x19, #ST_XHEAD]
	mov	x0, #-1
	cmp	w9, #3
	ccmp	w10, #0, #0, hs
	csel	x0, xzr, x0, eq
	ldr	w9, [x19, #ST_FRAG]
	add	x10, x19, #ST_TR
	mov	w11, #2
1:	ldr	x12, [x10], #8
	cbz	x12, 4f
	tbz	w9, #0, 2f
	ldp	w13, w14, [x12, #TR_FN]
	cmp	w14, w13
	b.hs	4f
	ldr	x15, [x12, #TR_FL]
	mov	w16, #24
	umaddl	x15, w14, w16, x15
	ldr	x15, [x15]
	b	3f
2:	ldr	w13, [x12, #TR_I]
	ldr	w14, [x12, #TR_N]
	ldr	x15, [x12, #TR_OFF]
	ldr	w16, [x12, #TR_CUR]
	ldr	x1, [x12, #TR_XLP]
	sub	x1, x1, #1
	cmp	w16, #1
	ccmp	x1, x15, #2, eq
	csel	x15, x1, x15, lo
	cmp	w13, w14
	b.lo	3f
	ldr	w13, [x12, #TR_MWAIT]     ; a Matroska or FLV cursor waiting for bytes: from where it reads on
	cbz	w13, 4f
	ldr	x15, [x12, #TR_XEND]
3:	cmp	x15, x0
	csel	x0, x15, x0, lo
4:	subs	w11, w11, #1
	b.ne	1b
	ret

; emit(stream) — every sample whose bytes are all in goes to its track's queue: listed by moof boxes, or a whole file's cursors in file order.
emit:
	FRAME	2
	mov	x20, x0
	ldr	w9, [x20, #ST_FRAG]
	cbz	w9, Lxe_loop
	tbnz	w9, #1, Lem_afs
	add	x21, x20, #ST_TR
	mov	w22, #2
Lem_track:
	ldr	x19, [x21], #8
	cbz	x19, Lem_next
Lem_sample:
	bl	q_wait
	b.hs	Lem_next
	ldp	w9, w10, [x19, #TR_FN]
	cmp	w10, w9
	b.hs	Lem_next
	ldr	x11, [x19, #TR_FL]
	mov	w12, #24
	umaddl	x11, w10, w12, x11        ; {offset, size, duration, composition, flags}
	ldr	x12, [x11]
	ldp	w2, w5, [x11, #8]
	ldp	x14, x15, [x20, #ST_ARPOS]
	add	w10, w10, #1
	ldr	x3, [x19, #TR_FDTS]
	add	x16, x3, x5
	subs	x1, x12, x14
	b.lo	Lem_lost                  ; before the arena: gone
	add	x13, x1, x2
	cmp	x13, x15
	b.hi	Lem_next                  ; not all here yet
	str	w10, [x19, #TR_FI]
	str	x16, [x19, #TR_FDTS]
	bl	aonly_drop
	b.eq	Lem_sample                ; Audio Only: not this picture
	ldrsw	x9, [x11, #16]
	ldr	w6, [x11, #20]
	ldr	x10, [x19, #TR_SHIFT]
	sub	x3, x3, x10
	add	x4, x3, x9
	ubfx	w6, w6, #16, #1
	eor	w6, w6, #1                ; sample_is_non_sync_sample clear: sync
	ldr	x0, [x20, #ST_ARBB]
	bl	mk_sample
	cbz	x0, Lem_sample
	bl	q_push
	b	Lem_sample
Lem_lost:
	str	w10, [x19, #TR_FI]
	str	x16, [x19, #TR_FDTS]
	b	Lem_sample
Lem_next:
	subs	w22, w22, #1
	b.ne	Lem_track
	b	Lret2
Lem_afs:
	ldr	x19, [x20, #ST_TR]
1:	bl	q_wait
	b.hs	Lret2
	bl	xs_win
	ldr	x9, [x19, #TR_OFF]
	cmp	x1, x9
	b.ls	2f
	mov	x3, #16384
	bl	Lafs_win
	b	1b
2:	ldr	x9, [x27, #E_DURMS]
	cbnz	x9, Lret2
	ldr	x9, [x19, #TR_FD]
	cbz	x9, Lret2
	bl	afs_dur
	b	Lret2

; aonly_drop — flags eq when Audio Only drops the track's samples: it is the playing picture (x19 = track; x9, x10 only).
aonly_drop:
	ldr	w9, [x28, #G_AONLY]
	ldr	x10, [x27, #E_VT]
	cmp	x10, x19
	ccmp	w9, #0, #4, eq
	ccmp	w9, w9, #0, ne
	ret

q_wait:
	ldp	w9, w10, [x19, #TR_FH]
	sub	w9, w10, w9
	ldr	w10, [x20, #ST_HUNGRY]
	cmp	w9, #(FIFO_N - 16)
	ccmp	wzr, w10, #0, hs
	ret

; box_done(stream) -> w0 = 1 when reading the collected box moved the stream elsewhere.
box_done:
	FRAME	2, 0, 1
	str	wzr, [x19, #ST_PST]
	ldr	w9, [x19, #ST_BOXT]
	ldp	x20, x21, [x19, #ST_BBUF]
	str	xzr, [x19, #ST_BBUF]      ; the box is its reader's now
	TYPE	w10, 'm','o','o','v'
	cmp	w9, w10
	b.eq	Lbd_moov
	TYPE	w10, 's','i','d','x'
	cmp	w9, w10
	b.eq	Lbd_sidx
	mov	x0, x19                   ; moof
	mov	x1, x20
	mov	x2, x21
	bl	on_moof
	mov	x0, x20
	bl	_free
	mov	w0, #0
	b	Lret2
Lbd_sidx:
	ldr	x0, [x19, #ST_SIDX]
	bl	_free
	str	x20, [x19, #ST_SIDX]
	ldr	x9, [x19, #ST_SPOS]
	str	x9, [x19, #ST_SIDXEND]
	ldr	x1, [x19, #ST_PEND]
	mov	w0, #0
	cmp	x1, #0
	b.le	Lret2
	mov	x0, x19                   ; a seek waited for it
	bl	st_seek
	mov	w0, #1
	b	Lret2
Lbd_moov:
	ldr	x22, [x19, #ST_MOOV]
	cbz	x22, 1f
	ldr	w9, [x19, #ST_KIND]
	cbnz	w9, 1f                    ; HLS: another variant's init segment
	mov	x0, x20                   ; one already read (a live stream repeats it)
	bl	_free
	mov	w0, #0
	b	Lret2
1:	str	x20, [x19, #ST_MOOV]
	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	bl	on_moov
	mov	w20, w0
	mov	x0, x22                   ; the tracks no longer read the old one
	bl	_free
	mov	w0, w20
	b	Lret2

mvhd_read:
	mov	w10, #0
	add	x9, x0, #32
	cmp	x9, x1
	b.hi	2f
	ldrb	w9, [x0]                  ; version: 32- or 64-bit times
	ldp	w10, w11, [x0, #12]
	rev	w11, w11
	cbz	w9, 1f
	ldr	w10, [x0, #20]
	ldr	x11, [x0, #24]
	rev	x11, x11
1:	rev	w10, w10                  ; movie timescale
	cbz	w10, 2f
	str	w10, [x27, #E_MTS]
2:	ret

; on_moov(stream, moov, length) -> w0 = 1 if the stream moved: its tracks, each fed by this stream, the first of each kind playing.
on_moov:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	add	x22, x1, x2
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'm','v','h','d'
	bl	box_find
	cbz	x0, Lmv_traks
	bl	mvhd_read
	cbz	w10, Lmv_traks
	ldr	x9, [x27, #E_DURMS]
	cbnz	x9, Lmv_traks             ; YouTube said it
	mov	x12, #1000
	mul	x11, x11, x12
	udiv	x11, x11, x10
	str	x11, [x27, #E_DURMS]
Lmv_traks:
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'm','v','e','x'
	bl	box_find
	mov	x23, x0                   ; fragmented when it has mvex
	mov	x24, x1
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x20, #ST_FRAG]
	mov	x25, x21
	add	x26, x20, #ST_TR          ; tracks the stream feeds already are read again, in order
	ldr	x9, [x26]
	cmp	x9, #0
	csel	x26, x26, xzr, ne
Lmv_trak:
	mov	x0, x25
	mov	x1, x22
	TYPE	w2, 't','r','a','k'
	bl	box_find
	cbz	x0, Lmv_done
	mov	x25, x1
	ldr	w2, [x20, #ST_FRAG]
	mov	x3, #0
	cbz	x26, 1f
	add	x9, x20, #(ST_TR + 16)
	cmp	x26, x9
	b.hs	Lmv_done
	ldr	x3, [x26]
	cbz	x3, Lmv_done
1:	bl	trak_open
	cbz	x0, Lmv_trak
	mov	x19, x0
	cbz	x26, 2f
	add	x26, x26, #8
	bl	trk_aim                   ; its units may have changed
	b	3f
2:	mov	x0, x20
	bl	trk_attach
	cbz	w0, Lmv_trak
3:	cbz	x23, 4f
	mov	x0, x23
	mov	x1, x24
	bl	trex_read
4:	ldr	w9, [x20, #ST_FRAG]
	cbnz	w9, Lmv_trak
	bl	trk_seek                 ; a whole file: its cursor at the target
	b	Lmv_trak
Lmv_done:
	mov	x0, x20
	bl	no_pic
	ldr	w9, [x20, #ST_FRAG]
	cbnz	w9, Lnil4
	ldr	x9, [x20, #ST_MDEND]
	cbz	x9, Lnil4              ; the media data follows
	mov	x0, x20                   ; it came first: back to it
	ldr	x1, [x27, #E_TGTMS]
	bl	st_seek
	mov	w0, #1
	b	Lret4
; trk_attach(stream) -> w0 = 1 when the track is fed by the stream, if it has room: its queue, its target; the first of its kind plays (x19 = track).
trk_attach:
	FRAME	1, 16
	mov	x20, x0
	add	x9, x20, #ST_TR
	ldr	x10, [x9]
	cbz	x10, 1f
	add	x9, x9, #8
	ldr	x10, [x9]
	cbnz	x10, Lta_no
1:	str	x9, [sp]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	cbz	x0, Lta_no
	ldr	x9, [sp]
	str	x0, [x19, #TR_FQ]
	str	x19, [x9]
	str	x20, [x19, #TR_ST]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	str	w9, [x19, #TR_STARVE]
	bl	trk_aim
	mov	w0, #1
	b	Lret1
Lta_no:
	mov	w0, #0
	b	Lret1

; trk_aim — the track's target from the last seek's, in its units; the first of its kind plays (x19 = track).
trk_aim:
	ldr	w9, [x19, #TR_KIND]
	add	x10, x27, #((E_VT >> 12) << 12)
	add	x10, x10, #(E_VT & 4095)
	cmp	w9, #'v'
	b.eq	1f
	add	x10, x10, #(E_AT - E_VT)
	cmp	w9, #'a'
	b.ne	2f                        ; subtitles: none until picked
1:	ldr	x11, [x10]
	cbnz	x11, 2f
	str	x19, [x10]
2:	ldr	x1, [x27, #E_TGTMS]
trk_tgt:
	ldr	w9, [x19, #TR_TS]
	mul	x1, x1, x9
	mov	x9, #1000
	udiv	x1, x1, x9
	str	x1, [x19, #TR_TGT]
	ret

; trk_new(stream, kind, timescale) -> x0 = a new track the stream feeds, or 0.
trk_new:
	FRAME	2
	mov	x20, x0
	mov	w21, w1
	mov	w22, w2
	mov	x0, #0
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lret2
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	stp	w21, w22, [x19, #TR_KIND]
	mov	x9, #-1
	str	x9, [x19, #TR_APTS]
	mov	x0, x20
	bl	trk_attach
	cmp	w0, #0
	csel	x0, x19, xzr, ne
	b	Lret2

; trex_read(mvex, end) — the track's fragment defaults: duration, size, flags (x19 = track).
trex_read:
	FRAME	1
	mov	x20, x1
1:	mov	x1, x20
	TYPE	w2, 't','r','e','x'
	bl	box_find
	cbz	x0, Lret1
	add	x9, x0, #24
	cmp	x9, x1
	b.hi	2f
	ldr	w9, [x0, #4]
	rev	w9, w9
	ldr	w10, [x19, #TR_ID]
	cmp	w9, w10
	b.ne	2f
	ldp	w9, w10, [x0, #12]
	rev	w9, w9
	rev	w10, w10
	ldr	w11, [x0, #20]
	rev	w11, w11
	stp	w9, w10, [x19, #TR_DDUR]
	str	w11, [x19, #TR_DFLAGS]
	b	Lret1
2:	mov	x0, x1
	b	1b

; on_moof(stream, moof, length) — list each of its tracks' samples: offsets in the stream, sizes, durations, composition offsets, flags.
	.equ MF_DEF,	0                 ; w: duration, size, flags
	.equ MF_BASE,	16                ; the base data offset
	.equ MF_NEXT,	24                ; where the next run's data starts
	.equ MF_AT,	32                ; the next box to look at
on_moof:
	FRAME	4, 48
	mov	x20, x0
	mov	x21, x1
	add	x22, x1, x2
	mov	x23, x21                  ; the next traf
Lmf_traf:
	mov	x0, x23
	mov	x1, x22
	TYPE	w2, 't','r','a','f'
	bl	box_find
	cbz	x0, Lret4
	mov	x23, x1
	mov	x24, x0                   ; this traf
	mov	x25, x1
	TYPE	w2, 't','f','h','d'
	bl	box_find
	cbz	x0, Lmf_traf
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lmf_traf
	ldr	w9, [x0]
	rev	w9, w9                    ; flags
	ldr	w10, [x0, #4]
	rev	w10, w10                  ; track_ID
	ldr	x19, [x20, #ST_TR]
	cbz	x19, Lmf_traf
	ldr	w11, [x19, #TR_ID]
	cmp	w11, w10
	b.eq	1f
	ldr	x19, [x20, #(ST_TR + 8)]
	cbz	x19, Lmf_traf
	ldr	w11, [x19, #TR_ID]
	cmp	w11, w10
	b.ne	Lmf_traf
1:	ldp	w12, w13, [x19, #TR_DDUR]
	ldr	w14, [x19, #TR_DFLAGS]
	ldr	x15, [x20, #ST_BOXPOS]    ; the moof's start
	add	x16, x0, #8
	tbz	w9, #0, 2f
	ldr	x15, [x16], #8
	rev	x15, x15                  ; base data offset
2:	tbz	w9, #1, 3f
	add	x16, x16, #4              ; sample description index
3:	tbz	w9, #3, 4f
	ldr	w12, [x16], #4
	rev	w12, w12
4:	tbz	w9, #4, 5f
	ldr	w13, [x16], #4
	rev	w13, w13
5:	tbz	w9, #5, 6f
	ldr	w14, [x16], #4
	rev	w14, w14
6:	cmp	x16, x1
	b.hi	Lmf_traf
	stp	w12, w13, [sp, #MF_DEF]
	str	w14, [sp, #(MF_DEF + 8)]
	stp	x15, x15, [sp, #MF_BASE]
	ldp	w9, w10, [x19, #TR_FN]
	subs	w26, w9, w10
	b.ne	8f
	stp	wzr, wzr, [x19, #TR_FN]   ; a new fragment's list
8:	mov	x0, x24
	mov	x1, x25
	TYPE	w2, 't','f','d','t'
	bl	box_find
	cbz	x0, Lmf_runs
	add	x9, x0, #8
	cmp	x9, x1
	b.hi	Lmf_runs
	ldrb	w9, [x0]
	ldr	w10, [x0, #4]
	rev	w10, w10
	cbz	w9, 1f
	ldr	x10, [x0, #4]
	rev	x10, x10
1:	cbnz	w26, 7f
	str	x10, [x19, #TR_FDTS]
7:	ldr	w9, [x20, #ST_KIND]
	cbz	w9, Lmf_runs
	ldr	w12, [x19, #TR_TS]        ; HLS: one timeline for every stream, anchored at the first decode time less its segment's start (90 kHz)
	mov	x13, #(90000 & 0xffff)
	movk	x13, #(90000 >> 16), lsl #16
	mul	x14, x10, x13
	udiv	x1, x14, x12
	mov	x0, x20
	bl	t33_time
	sub	x11, x1, x4
	mul	x14, x11, x12
	sdiv	x14, x14, x13
	str	x14, [x19, #TR_SHIFT]
Lmf_runs:
	str	x24, [sp, #MF_AT]
Lmf_run:
	ldr	x0, [sp, #MF_AT]
	mov	x1, x25
	TYPE	w2, 't','r','u','n'
	bl	box_find
	cbz	x0, Lmf_traf
	str	x1, [sp, #MF_AT]
	mov	x2, sp
	bl	trun_read
	b	Lmf_run

; trun_read(trun, end, state) — append a run's samples to the track's list; state = {defaults, base, next} (x19 = track).
trun_read:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	add	x9, x20, #8
	cmp	x9, x21
	b.hi	Lret4
	ldr	w23, [x20]
	rev	w23, w23                  ; flags
	ldr	w24, [x20, #4]
	rev	w24, w24                  ; samples
	add	x25, x20, #8
	ldr	x26, [x22, #MF_NEXT]
	tbz	w23, #0, 1f
	ldr	w9, [x25], #4
	rev	w9, w9
	sxtw	x9, w9
	ldr	x26, [x22, #MF_BASE]
	add	x26, x26, x9              ; base + data offset
1:	mov	w11, #0
	tbz	w23, #2, 2f
	ldr	w11, [x25], #4            ; the first sample's flags
	rev	w11, w11
2:	ubfx	w9, w23, #8, #4
	fmov	s0, w9
	cnt	v0.8b, v0.8b
	fmov	w9, s0
	lsl	w9, w9, #2                ; bytes per sample record
	umaddl	x10, w24, w9, x25
	cmp	x10, x21
	b.hi	Lret4                     ; cut short
	stp	w11, w9, [sp, #-16]!
	ldp	w9, w10, [x19, #TR_FN]
	ldr	w12, [x19, #TR_FCAP]
	add	w13, w9, w24
	cmp	w13, w12
	b.ls	3f
	ldr	x0, [x19, #TR_FL]         ; the list grows
	mov	w9, #24
	umull	x1, w13, w9
	str	w13, [x19, #TR_FCAP]
	bl	_realloc
	cbz	x0, Ltr_none
	str	x0, [x19, #TR_FL]
3:	ldp	w11, w9, [sp], #16
	ldr	w10, [x19, #TR_FN]
	ldr	x12, [x19, #TR_FL]
	mov	w13, #24
	umaddl	x12, w10, w13, x12        ; the first new entry
	add	w10, w10, w24
	str	w10, [x19, #TR_FN]
	mov	w13, #0                   ; sample index
Ltr_sample:
	cmp	w13, w24
	b.hs	Ltr_end
	ldr	w14, [x22, #MF_DEF]       ; duration
	ldr	w15, [x22, #(MF_DEF + 4)] ; size
	ldr	w16, [x22, #(MF_DEF + 8)] ; flags
	cbnz	w13, 4f
	tbz	w23, #2, 4f
	mov	w16, w11
4:	mov	w17, #0                   ; composition offset
	tbz	w23, #8, 5f
	ldr	w14, [x25], #4
	rev	w14, w14
5:	tbz	w23, #9, 6f
	ldr	w15, [x25], #4
	rev	w15, w15
6:	tbz	w23, #10, 7f
	ldr	w16, [x25], #4
	rev	w16, w16
7:	tbz	w23, #11, 8f
	ldr	w17, [x25], #4
	rev	w17, w17
8:	str	x26, [x12]
	stp	w15, w14, [x12, #8]
	stp	w17, w16, [x12, #16]
	add	x12, x12, #24
	add	x26, x26, x15
	add	w13, w13, #1
	b	Ltr_sample
Ltr_end:
	str	x26, [x22, #MF_NEXT]
	b	Lret4
Ltr_none:
	add	sp, sp, #16
	stp	wzr, wzr, [x19, #TR_FN]   ; no memory: the list is lost
	str	wzr, [x19, #TR_FCAP]
	str	xzr, [x19, #TR_FL]
	b	Lret4

; st_open(stream, url) — start a stream from its first byte (the URL is the stream's); its size from the URL's clen, if any.
st_open:
	FRAME	1, 0, 1
	str	x1, [x19, #ST_URL]
	mov	x0, x1
	CSTR	x1, "clen="
	bl	_strstr
	cbz	x0, 1f
	add	x0, x0, #5
	bl	strtol10
	str	x0, [x19, #ST_LEN]
1:	mov	x0, x19
	bl	st_pump
	b	Lret1

; st_close(stream) — stop it and free what it keeps.
st_close:
	FRAME	2, 0, 1
	bl	st_reset
	adr	x20, Lst_owned
1:	ldrh	w9, [x20], #2
	cmp	w9, #1
	b.eq	Lret2                     ; the end mark (0 is ST_URL)
	ldr	x0, [x19, x9]
	str	xzr, [x19, x9]            ; it may open again
	bl	_free
	b	1b
Lst_owned:	                          ; what a stream allocates
	.short	ST_URL, ST_MOOV, ST_SIDX, ST_TXT, ST_PLURL, ST_PL, ST_KEYURL, ST_MAPURL, ST_RQURL, ST_VPES, ST_APES, ST_VPEN, ST_XIDX, ST_XKEYS, 1
	.p2align 2

; ---- HLS: playlists, their segments (TS, fMP4, packed audio), the variant the network allows (media queue) ----

; line_end(p) -> x0 = the end of p's line, less trailing white space; x1 = the next line.
line_end:
	mov	x9, x0
1:	ldrb	w10, [x9]
	cbz	w10, 2f
	cmp	w10, #'\n'
	b.eq	2f
	add	x9, x9, #1
	b	1b
2:	mov	x1, x9
	cbz	w10, 3f
	add	x1, x9, #1
3:	cmp	x9, x0
	b.ls	4f
	ldurb	w10, [x9, #-1]
	cmp	w10, #' '
	b.hi	4f
	sub	x9, x9, #1
	b	3b
4:	mov	x0, x9
	ret

; attr(line, end, name) -> x0 = name's value in [line, end), without quotes, x1 = its end; x0 = 0 if absent (name ends with '=').
attr:
	FRAME	2, 0, 1
	mov	x21, x2
	mov	x0, x2
	bl	_strlen
	mov	x22, x0
La_find:
	mov	x0, x19
	mov	x1, x21
	sub	x2, x20, x19
	bl	_strnstr
	cbz	x0, Lret2
	add	x19, x0, #1               ; inside a longer name: look again after it
	ldurb	w9, [x0, #-1]
	mov	w10, #','
	cmp	w9, #':'
	ccmp	w9, w10, #4, ne
	b.ne	La_find
	add	x0, x0, x22
	mov	x1, x0
	ldrb	w9, [x0]
	cmp	w9, #'"'
	b.ne	La_bare
	add	x0, x0, #1
	mov	x1, x0
1:	cmp	x1, x20
	b.hs	Lret2
	ldrb	w9, [x1]
	cmp	w9, #'"'
	b.eq	Lret2
	add	x1, x1, #1
	b	1b
La_bare:
	cmp	x1, x20
	b.hs	Lret2
	ldrb	w9, [x1]
	cmp	w9, #','
	b.eq	Lret2
	add	x1, x1, #1
	b	La_bare

; attr_num(line, name) -> x0 = name's decimal value in the line, 0 if absent.
attr_num:
	FRAME	1, 0, 1
	bl	line_end
	mov	x1, x0
	mov	x0, x19
	mov	x2, x20
	bl	attr
	cbz	x0, Lret1
	bl	strtol10
	b	Lret1

; seg_scan(stream, mode, value, out) -> w0 = 1 with out the media playlist's segment: mode 0 by media sequence number, 1 by time (ms); out's playlist fields are filled either way.
seg_scan:
	FRAME	4, 16
	mov	x19, x3
	mov	w20, w1
	mov	x21, x2
	ldr	x22, [x0, #ST_PL]
	mov	x0, x19
	mov	x1, #SG_SIZE
	bl	_bzero
	str	xzr, [sp]                 ; where a range without offset starts
	mov	x23, #0                   ; time so far
	mov	x24, #0                   ; the coming segment's duration
	mov	w26, #0                   ; segments passed
	cbz	x22, Lsg_none
Lsg_line:
	ldrb	w9, [x22]
	cbz	w9, Lsg_none
	cmp	w9, #'#'
	b.eq	Lsg_tag
	cmp	w9, #' '
	b.ls	Lsg_next
	ldr	x9, [x19, #SG_SEQ0]       ; a segment's URI
	add	x9, x9, w26, uxtw
	cbnz	w20, 1f
	cmp	x9, x21
	b.eq	Lsg_hit
	b	Lsg_pass
1:	add	x10, x23, x24
	cmp	x10, x21
	b.gt	Lsg_hit
Lsg_pass:
	add	w26, w26, #1
	add	x23, x23, x24
	mov	x24, #0
	ldp	x10, x11, [x19, #SG_BRL]
	add	x10, x10, x11
	str	x10, [sp]
	str	xzr, [x19, #SG_BRL]
	strb	wzr, [x19, #(SG_DSEQ + 3)]
	b	Lsg_next
Lsg_hit:
	str	x9, [x19, #SG_SEQ]
	mov	x0, x22
	bl	line_end
	stp	x22, x0, [x19, #SG_URI]
	stp	x23, x24, [x19, #SG_T]
	str	w26, [x19, #SG_N]
	mov	w0, #1
	b	Lret4
Lsg_tag:
	ldrb	w9, [x22, #4]
	cmp	w9, #'I'
	b.eq	Lsg_inf                   ; #EXTINF:
	cmp	w9, #'-'
	b.ne	Lsg_next
	ldrh	w9, [x22, #7]             ; #EXT-X-...
	mov	w10, #('B' | 'Y' << 8)    ; BYTERANGE, not BITRATE
	cmp	w9, w10
	b.eq	Lsg_br
	mov	w10, #('D' | 'I' << 8)
	cmp	w9, w10
	b.eq	Lsg_disc
	and	w9, w9, #0xff
	cmp	w9, #'K'
	b.eq	Lsg_key
	cmp	w9, #'T'
	b.eq	Lsg_tdur
	cmp	w9, #'E'
	b.eq	Lsg_end
	cmp	w9, #'M'
	b.ne	Lsg_next
	ldrb	w9, [x22, #8]
	cmp	w9, #'A'
	b.eq	Lsg_map
	add	x0, x22, #22              ; #EXT-X-MEDIA-SEQUENCE:
	bl	strtol10
	str	x0, [x19, #SG_SEQ0]
	b	Lsg_next
Lsg_inf:
	add	x0, x22, #8
	mov	x1, #0
	CALLF	strtod
	mov	x9, #1000
	scvtf	d1, x9
	fmul	d0, d0, d1
	fcvtns	x24, d0
	b	Lsg_next
Lsg_br:
	add	x0, x22, #17              ; #EXT-X-BYTERANGE:n[@o]
	add	x1, sp, #8
	mov	w2, #10
	bl	_strtol
	str	x0, [x19, #SG_BRL]
	ldr	x11, [sp]
	ldr	x9, [sp, #8]
	ldrb	w10, [x9]
	cmp	w10, #'@'
	b.ne	1f
	add	x0, x9, #1
	bl	strtol10
	mov	x11, x0
1:	str	x11, [x19, #SG_BRO]
	b	Lsg_next
Lsg_key:
	add	x0, x22, #11              ; #EXT-X-KEY:METHOD=NONE ends encryption
	CSTR	x1, "METHOD=NONE"
	mov	x2, #11
	bl	_strncmp
	cmp	w0, #0
	csel	x9, xzr, x22, eq
	str	x9, [x19, #SG_KEY]
	b	Lsg_next
Lsg_map:
	str	x22, [x19, #SG_MAP]
	b	Lsg_next
Lsg_tdur:
	add	x0, x22, #22
	bl	strtol10
	mov	x9, #1000
	mul	x0, x0, x9
	str	w0, [x19, #SG_TDUR]
	b	Lsg_next
Lsg_end:
	mov	w9, #1
	str	w9, [x19, #SG_END]
	b	Lsg_next
Lsg_disc:
	ldr	w0, [x19, #SG_DSEQ]
	add	w0, w0, #1
	orr	w0, w0, #(1 << 31)
	ldrb	w9, [x22, #20]
	cmp	w9, #' '
	b.ls	1f
	add	x0, x22, #30              ; DISCONTINUITY-SEQUENCE
	bl	strtol10
1:	str	w0, [x19, #SG_DSEQ]
Lsg_next:
	mov	x0, x22
	bl	line_end
	mov	x22, x1
	b	Lsg_line
Lsg_none:
	str	w26, [x19, #SG_N]
	str	x23, [x19, #SG_T]         ; the playlist's length
	b	Lnil4

; url_join(base, uri, end) -> x0 = the absolute URL (malloc) of a URI in [uri, end), relative to base; 0 if not one (media queue).
url_join:
	VM	Lp_ujoin
	.pushsection __DATA,__data
Lp_ujoin:
	GL	2
	SUBL	1
	FI
	FOPK	4, 4095 * 16              ; at most 4095 bytes of it
	FT
	ADDI	1
	SL	2
	CALL	F_strlcpy, "Bbc"
	.short	B_UJ
	NCALL	mkurl, "=a"
	SL	3
	NCALL	mkstr, "=B"
	.short	B_UJ
	SL	4
	CLS	NSURL
	MSG	S_URLWithString_relativeToURL_, "=ed"
	MSG	S_absoluteString, "="
	MSG	S_UTF8String, "="
	JZ	Lp_ujoin_end
	CALL	F_strdup, "=V"
	HERE	Lp_ujoin_end
	OP_END
	.popsection

; hls_pick() -> w0 = 1 with the master playlist's variant for the measured speed as the first stream's playlist, and the first time its sound rendition as the second's.
hls_pick:
	VM	Lp_hpick
	.pushsection __DATA,__data
Lp_hpick:
	LDE	E_BPS
	JZ	Lp_hpk_start
	DIVH	5
	SHL	2                         ; four fifths of the measured speed
	JMP	Lp_hpk_target
	HERE	Lp_hpk_start
	IMM	0
	ADDH	BPS_START / 64
	MULH	64
	HERE	Lp_hpk_target
	SL	5                         ; f: the target
	IMM	0
	SL	1                         ; b: the best line that fits, c: its bandwidth
	SL	2
	SL	3                         ; d: the lowest, e: its bandwidth
	IMM	1
	SHL	62
	SL	4
	LDE	E_MASTER
	SL	0                         ; a: the line
	CALL	F_strstr, "=aP"
	.long	Ls_aac - Lvm_base
	SL	6                         ; g: the master lists AAC-LC
	HERE	Lp_hpk_line
	GL	0
	LDB	0
	JZ	Lp_hpk_done
	CALL	F_strncmp, ">aPI"
	.long	Ls_xstream - Lvm_base
	.byte	18
	JNZ	Lp_hpk_next
	GL	6
	JZ	Lp_hpk_any
	NCALL	line_end, "=a"            ; AAC-LC variants only, when there are any
	SUBL	0
	SL	7
	CALL	F_strnstr, "=aPh"
	.long	Ls_aac - Lvm_base
	JZ	Lp_hpk_next
	HERE	Lp_hpk_any
	NCALL	attr_num, "=aC"
	.asciz	"BANDWIDTH="
	SL	7
	SUBL	4
	LT	0
	JZ	Lp_hpk_fit
	GL	7
	SL	4
	GL	0
	SL	3
	HERE	Lp_hpk_fit
	GL	5
	SUBL	7
	LT	0
	JNZ	Lp_hpk_next               ; over the target
	GL	2
	SUBL	7
	LT	0
	JZ	Lp_hpk_next
	GL	7
	SL	2
	GL	0
	SL	1
	HERE	Lp_hpk_next
	NCALL	line_end, "?a"
	GL	7
	SL	0
	JMP	Lp_hpk_line
	HERE	Lp_hpk_done
	GL	1
	JNZ	Lp_hpk_chosen
	GL	3                         ; none fits: the lowest
	SL	1
	JNZ	Lp_hpk_chosen
	OP_END
	HERE	Lp_hpk_chosen
	NCALL	line_end, "?b"            ; its URI: the next line that is not a tag
	GL	7
	SL	0
	HERE	Lp_hpk_uri
	GL	0
	LDB	0
	JNZ	Lp_hpk_char
	OP_END
	HERE	Lp_hpk_char
	SL	2
	EQ	'#'
	JNZ	Lp_hpk_skip
	GL	2
	LT	33
	JZ	Lp_hpk_url
	HERE	Lp_hpk_skip
	NCALL	line_end, "?a"
	GL	7
	SL	0
	JMP	Lp_hpk_uri
	HERE	Lp_hpk_url
	NCALL	line_end, "=a"
	SL	7
	LDE	E_MURL
	NCALL	url_join, "=Vah"
	JNZ	Lp_hpk_set
	OP_END
	HERE	Lp_hpk_set
	SL	2
	NCALL	pl_set, "Bc"
	.short	E_ST
	LDEW	E_ST + ST_SIZE + ST_KIND
	JZ	Lp_hpk_sound
	HERE	Lp_hpk_yes1               ; the sound rendition was chosen already
	IMM	1
	OP_END
	HERE	Lp_hpk_sound
	GL	1                         ; its sound: AUDIO="group" names an EXT-X-MEDIA with a URI
	NCALL	line_end, "=V"
	SL	7
	NCALL	attr, "?bhC"
	.asciz	"AUDIO="
	JZ	Lp_hpk_yes1
	SL	2                         ; c: the group's name, d: its length
	GL	7
	SUBL	2
	SL	3
	IMM	0
	SL	4                         ; e: the rendition chosen
	LDE	E_MASTER
	SL	0
	HERE	Lp_hpk_media
	NCALL	media_next, "?aP"
	.long	Ls_taudio - Lvm_base
	JZ	Lp_hpk_found
	SL	5                         ; f: the line, b: its end
	GL	7
	SL	1
	LDE	B_MNEXT
	SL	0
	NCALL	attr, "?fbP"
	.long	Ls_group - Lvm_base
	JZ	Lp_hpk_media
	SL	6
	GL	7
	SUBL	6
	EQL	3
	JZ	Lp_hpk_media
	CALL	F_strncmp, ">gcd"
	JNZ	Lp_hpk_media
	NCALL	attr, "=fbP"
	.long	Ls_uri - Lvm_base
	JZ	Lp_hpk_media              ; in the variant's own segments
	GL	4
	JNZ	Lp_hpk_def
	GL	5
	SL	4                         ; the first, unless a default follows
	HERE	Lp_hpk_def
	GL	1
	SUBL	5
	SL	7
	CALL	F_strnstr, "=fCh"
	.asciz	"DEFAULT=YES"
	JZ	Lp_hpk_media
	GL	5
	SL	4
	HERE	Lp_hpk_found
	GL	4
	JZ	Lp_hpk_yes
	NCALL	line_end, "=V"
	SL	7
	NCALL	attr, "?ehP"
	.long	Ls_uri - Lvm_base
	SL	6
	LDE	E_MURL
	NCALL	url_join, "=Vgh"
	JZ	Lp_hpk_yes
	SL	2
	NCALL	pl_set, "Bc"
	.short	E_ST + ST_SIZE
	HERE	Lp_hpk_yes
	IMM	1
	OP_END
	.popsection

; pl_set(stream, url) — the stream plays that media playlist (the URL becomes its); a new one is loaded at the next segment.
pl_set:
	FRAME	1, 0, 1
	ldr	x0, [x19, #ST_PLURL]
	cbz	x0, 1f
	mov	x1, x20
	bl	_strcmp
	cbnz	w0, 1f
	mov	x0, x20                   ; the same one
	bl	_free
	b	Lret1
1:	ldr	x0, [x19, #ST_PLURL]
	bl	_free
	str	x20, [x19, #ST_PLURL]
	mov	w9, #1
	str	w9, [x19, #ST_KIND]
	str	w9, [x19, #ST_STALE]
	b	Lret1

; st_get(stream, url, type, first, length) — request a URL for the stream (type: ST_REQT); bytes from first, length of them (0: all, or CHUNK of a stream's bytes).
	.equ GT_BUF,	16
st_get:
	FRAME	3, 80, 1
	mov	w22, w2
	mov	x23, x3
	mov	x24, x4
	mov	x21, x1
	str	w2, [x19, #ST_REQT]
	mov	x0, x1
	bl	mkreq
	cbz	x0, Lpu_end
	mov	x20, x0
	cbnz	x24, 1f
	cbnz	w22, Lgt_go               ; a whole text or segment
	mov	x24, #CHUNK               ; a stream's bytes: googlevideo slows anything larger to real time
	ldr	x11, [x19, #ST_LEN]
	sub	x12, x11, x23
	cmp	x11, #0
	ccmp	x24, x12, #0, ne
	csel	x24, x12, x24, hi
1:	add	x10, x23, x24
	sub	x10, x10, #1
	stp	x23, x10, [sp]
	add	x0, sp, #GT_BUF
	mov	x1, #64
	GADDR	x2, Ls_bytes
	bl	_snprintf
	add	x0, sp, #GT_BUF
	bl	mkstr
	mov	x23, x0
	GADDR	x0, Ls_range
	bl	mkstr
	mov	x3, x0
	mov	x2, x23
	mov	x0, x20
	SEND	S_setValue_forHTTPHeaderField_
Lgt_go:
	mov	x0, x21
	GADDR	x1, Ls_gvideo
	bl	_strstr
	cbz	x0, 2f
	mov	x0, x20                   ; YouTube's CDN speaks QUIC
	mov	w2, #1
	SEND	S_setAssumesHTTP3Capable_
2:	adr	x9, st_sink
	adr	x10, st_done
	stp	x9, x10, [x19, #(ST_RQ + RQ_SINK)]
	str	x20, [x19, #(ST_RQ + RQ_REQ)]
	mov	w9, #1
	str	w9, [x19, #ST_FETCH]
	ldr	x9, [x19, #ST_SEGOFF]
	str	xzr, [x19, #ST_GOT]
	str	wzr, [x19, #ST_ANS]
	str	x9, [x19, #ST_SKIP]
	str	xzr, [x19, #ST_TXTN]
	bl	now_ns
	str	x0, [x19, #ST_T1]
	add	x0, x19, #ST_RQ
	bl	Lnet_start
	b	Lret3

; st_get_own(stream, url, type, first, length) — st_get with a URL (malloc) the stream keeps until its next request.
st_get_own:
	FRAME	3, 0, 1
	mov	w21, w2
	mov	x22, x3
	mov	x23, x4
	ldr	x0, [x19, #ST_RQURL]
	bl	_free
	str	x20, [x19, #ST_RQURL]
	mov	x0, x19
	mov	x1, x20
	mov	w2, w21
	mov	x3, x22
	mov	x4, x23
	bl	st_get
	b	Lret3

; st_later(ms, stream) — st_pump for the stream after half that long: a retry, or a live playlist's reload.
st_later:
	FRAME	1
	mov	x19, x1
	mov	w9, #1
	str	w9, [x19, #ST_RETRY]
	mov	w9, #(500000 & 0xffff)
	movk	w9, #(500000 >> 16), lsl #16
	umull	x1, w0, w9
	mov	x0, #0
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	mov	x2, x19
	adr	x3, st_retry
	bl	_dispatch_after_f
	b	Lret1

; seg_reset(stream) — a new segment: no partial TS packet or PES, the box parser at a box.
seg_reset:
	str	xzr, [x0, #(ST_VPEN + 8)]
	str	wzr, [x0, #ST_TSN]
	str	xzr, [x0, #(ST_VPES + 8)]
	str	xzr, [x0, #(ST_APES + 8)]
	stp	wzr, wzr, [x0, #ST_PST]
	ret

; hexbyte(hi, lo) -> w9 = the byte two hex digits spell (w9, w10 in).
hexbyte:
	orr	w9, w9, #0x20
	orr	w10, w10, #0x20
	sub	w9, w9, #'0'
	cmp	w9, #10
	b.lo	1f
	sub	w9, w9, #('a' - '0' - 10)
1:	sub	w10, w10, #'0'
	cmp	w10, #10
	b.lo	2f
	sub	w10, w10, #('a' - '0' - 10)
2:	orr	w9, w10, w9, lsl #4
	ret

; hls_pump(stream) — an HLS stream's next request: its playlist when due, the segment's key or init segment once, then the segment.
	.equ HP_SEG,	16
	.equ HP_SIZE,	HP_SEG + SG_SIZE
hls_pump:
	FRAME	3, HP_SIZE, 1
Lhp_again:
	ldr	x9, [x19, #ST_PL]
	ldr	w10, [x19, #ST_STALE]
	cmp	x9, #0
	ccmp	w10, #0, #0, ne
	b.ne	Lhp_list
	mov	x0, x19
	mov	w1, #0
	ldr	x2, [x19, #ST_SEQ]
	add	x3, sp, #HP_SEG
	bl	seg_scan
	cbnz	w0, Lhp_seg
	ldr	x9, [sp, #(HP_SEG + SG_SEQ0)]
	ldr	x10, [x19, #ST_SEQ]
	cmp	x10, x9
	b.lo	Lhp_behind
	ldr	w9, [sp, #(HP_SEG + SG_END)]
	cbnz	w9, Lpu_end
	mov	w9, #1                    ; live, not out yet: the playlist again in half a target duration
	str	w9, [x19, #ST_STALE]
	ldr	w0, [sp, #(HP_SEG + SG_TDUR)]
Lhp_later:
	mov	x1, x19
	bl	st_later
	b	Lret3
Lhp_behind:
	str	x9, [x19, #ST_SEQ]        ; out of the live window: its oldest
	b	Lhp_again
Lhp_list:
	ldr	x0, [x19, #ST_PLURL]
	bl	_strdup
	mov	x1, x0
	mov	x0, x19
	mov	w2, #1
Lhp_whole:
	mov	x3, #0
	mov	x4, #0
	bl	st_get_own
	b	Lret3
Lhp_seg:
	ldr	x9, [sp, #(HP_SEG + SG_T)]
	ldr	x10, [x19, #ST_PLOFF]
	add	x9, x9, x10
	ldr	x10, [sp, #(HP_SEG + SG_SEQ)]
	ldp	x12, x11, [x19, #ST_SEGN]
	stp	x10, x9, [x19, #ST_SEGN]
	cmp	x12, x10
	ccmp	x12, #0, #4, eq
	b.ne	1f
	cmp	x12, #0
	csel	x12, x10, x12, eq
	csel	x11, x9, x11, eq
	str	x11, [x27, #E_MTIME]
	str	x12, [x27, #E_MSEQ]
	ldr	w9, [sp, #(HP_SEG + SG_DSEQ)] ; a discontinuity: the timeline is anchored again
	ldr	x10, [x19, #ST_T0]
	ubfx	x10, x10, #33, #30
	add	w11, w10, w9, lsr #31
	csel	w11, w10, w11, eq
	and	w9, w9, #((1 << 24) - 1)
	cmp	w9, w11
	csel	w9, w9, w11, hi
	cmp	w9, w10
	b.eq	1f
	ubfiz	x9, x9, #33, #30
	str	x9, [x19, #ST_T0]
1:	BADDR	x9, (E_ST + 2 * ST_SIZE)
	ldr	x10, [x19, #ST_T0]
	orr	x10, x10, #(1 << 63)
	ldr	x11, [x27, #E_T0]
	cmp	x19, x9
	ccmp	x10, x11, #0, eq
	mov	w0, #200
	b.hi	Lhp_later
	str	wzr, [x19, #ST_ENC]
	ldr	x20, [sp, #(HP_SEG + SG_KEY)]
	cbz	x20, Lhp_map
	mov	x0, x20                   ; AES-128: its key, fetched once
	bl	line_end
	mov	x21, x0
	mov	x1, x0
	mov	x0, x20
	GADDR	x2, Ls_uri
	bl	attr
	cbz	x0, Lhp_map
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x19, #ST_PLURL]
	bl	url_join
	cbz	x0, Lhp_map
	mov	x22, x0
	ldr	x1, [x19, #ST_KEYURL]
	cbz	x1, 2f
	bl	_strcmp
	cbz	w0, 3f
2:	mov	x0, x19
	mov	x1, x22
	mov	w2, #2
	b	Lhp_whole
3:	mov	x0, x22
	bl	_free
	mov	w9, #1
	str	w9, [x19, #ST_ENC]
	ldr	x9, [x19, #ST_SEQ]        ; its IV: given, else the media sequence number
	rev	x9, x9
	stp	xzr, x9, [x19, #ST_IV]
	mov	x0, x20
	mov	x1, x21
	CSTR	x2, "IV="
	bl	attr
	cbz	x0, Lhp_map
	add	x11, x0, #2               ; 0x and 32 hex digits
	add	x12, x19, #ST_IV
	mov	w13, #16
4:	ldrb	w9, [x11], #1
	ldrb	w10, [x11], #1
	bl	hexbyte
	strb	w9, [x12], #1
	subs	w13, w13, #1
	b.ne	4b
Lhp_map:
	ldr	x20, [sp, #(HP_SEG + SG_MAP)]
	cbz	x20, Lhp_get
	mov	x0, x20                   ; fMP4: its init segment, read once
	bl	line_end
	mov	x21, x0
	mov	x1, x0
	mov	x0, x20
	GADDR	x2, Ls_uri
	bl	attr
	cbz	x0, Lhp_get
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x19, #ST_PLURL]
	bl	url_join
	cbz	x0, Lhp_get
	mov	x22, x0
	ldr	x1, [x19, #ST_MAPURL]
	cbz	x1, 5f
	bl	_strcmp
	cbz	w0, 6f
5:	mov	x0, x20                   ; its range, if given: "n@o"
	mov	x1, x21
	CSTR	x2, "BYTERANGE="
	bl	attr
	mov	x3, #0
	mov	x4, #0
	cbz	x0, 7f
	add	x1, sp, #(HP_SEG + SG_BRL)
	mov	w2, #10
	bl	_strtol
	mov	x4, x0
	mov	x3, #0
	ldr	x9, [sp, #(HP_SEG + SG_BRL)]
	ldrb	w10, [x9]
	cmp	w10, #'@'
	b.ne	7f
	str	x4, [sp, #(HP_SEG + SG_BRO)]
	add	x0, x9, #1
	bl	strtol10
	mov	x3, x0
	ldr	x4, [sp, #(HP_SEG + SG_BRO)]
7:	stp	wzr, wzr, [x19, #ST_PST]
	mov	x0, x19
	mov	x1, x22
	mov	w2, #4
	bl	st_get_own
	b	Lret3
6:	mov	x0, x22
	bl	_free
Lhp_get:
	ldr	x9, [x19, #ST_SEGOFF]
	cbnz	x9, 1f
	str	wzr, [x19, #ST_SEGF]
	mov	x0, x19
	bl	seg_reset
1:	ldr	x0, [x19, #ST_PLURL]
	ldp	x1, x2, [sp, #(HP_SEG + SG_URI)]
	bl	url_join
	cbz	x0, Lpu_end
	mov	x1, x0
	mov	x0, x19
	mov	w2, #3
	ldp	x4, x3, [sp, #(HP_SEG + SG_BRL)]
	bl	st_get_own
	b	Lret3

; hls_text(stream) — a playlist or key came whole: a master picks its variant and sound, a media playlist replaces the last (the first sets where to start), a key is kept.
	.equ HT_SEG,	0
hls_text:
	FRAME	2, SG_SIZE, 1
	ldr	x20, [x19, #ST_TXT]
	stp	xzr, xzr, [x19, #ST_TXT]  ; the text is its reader's now
	cbz	x20, Lret2
	ldr	w9, [x19, #ST_REQT]
	cmp	w9, #2
	b.ne	Lht_list
	ldr	q0, [x20]                 ; the key
	str	q0, [x19, #ST_KEY]
	mov	x0, x20
	bl	_free
	ldr	x0, [x19, #ST_KEYURL]
	bl	_free
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x19, #ST_KEYURL]
	str	xzr, [x19, #ST_RQURL]
	b	Lht_pump
Lht_list:
	mov	x0, x20
	GADDR	x1, Ls_xstream
	bl	_strstr
	cbz	x0, Lht_media
	ldr	x9, [x27, #E_MASTER]      ; a master playlist, once
	cbnz	x9, Lht_drop
	str	x20, [x27, #E_MASTER]
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x27, #E_MURL]
	str	xzr, [x19, #ST_RQURL]
	bl	hls_pick
	cbz	w0, Lsd_end
	ldr	w9, [x27, #(E_ST + ST_SIZE + ST_KIND)]
	cbz	w9, Lht_pump              ; no sound rendition
	BADDR	x0, (E_ST + ST_SIZE)
	bl	st_pump
	ldr	w9, [x28, #G_AONLY]
	cbz	w9, Lht_pump
	b	Lret2
Lht_media:
	ldr	x0, [x19, #ST_PL]
	bl	_free
	str	x20, [x19, #ST_PL]
	str	wzr, [x19, #ST_STALE]
	ldr	w9, [x19, #ST_ENDED]
	cbnz	w9, 3f
	ldp	x2, x20, [x19, #ST_SEGN]
	cbnz	x2, 5f
	ldr	x2, [x27, #E_MSEQ]
	ldr	x20, [x27, #E_MTIME]
5:	mov	x0, x19
	mov	w1, #0
	mov	x3, sp
	bl	seg_scan
	cbz	w0, 3f
	ldr	x10, [sp, #SG_T]
	sub	x9, x20, x10
	str	x9, [x19, #ST_PLOFF]
3:	ldr	x9, [x19, #ST_SEQ]
	cbnz	x9, Lht_pump              ; already playing: it goes on from its sequence number
	mov	x0, x19                   ; the first: the whole playlist read, its length and end
	mov	w1, #1
	mov	x2, #0x7fffffffffffffff
	mov	x3, sp
	bl	seg_scan
	ldr	w9, [sp, #SG_TDUR]
	str	w9, [x19, #ST_TDUR]
	ldr	w9, [sp, #SG_END]
	str	w9, [x19, #ST_ENDED]
	ldr	x21, [x27, #E_MSEQ]
	cbnz	w9, 1f
	ldr	x9, [x19, #ST_PEND]
	cmp	x9, #0
	ccmp	x21, #0, #4, gt
	b.ne	2f
4:	ldr	x10, [sp, #SG_SEQ0]       ; live: a few segments from its live edge, no length
	ldr	w11, [sp, #SG_N]
	subs	w11, w11, #HLS_LIVE_BACK
	csel	w11, w11, wzr, gt
	add	x10, x10, w11, uxtw
	str	x10, [x19, #ST_SEQ]
	cbnz	x21, Lht_pump
	mov	x0, x19
	mov	w1, #0
	mov	x2, x10
	mov	x3, sp
	bl	seg_scan
	ldr	x9, [sp, #SG_T]
	neg	x9, x9
	str	x9, [x19, #ST_PLOFF]
	b	Lht_pump
1:	str	xzr, [x19, #ST_PLOFF]
	ldr	x9, [x27, #E_DURMS]       ; on demand: its length, then the segment of the target
	cbnz	x9, 2f
	ldr	x9, [sp, #SG_T]
	str	x9, [x27, #E_DURMS]
2:	mov	x0, x19
	mov	w1, #1
	ldp	x9, x2, [x19, #ST_PLOFF]  ; where it was sought
	sub	x2, x2, x9
	mov	x3, sp
	bl	seg_scan
	cbz	w0, 4b
	ldr	x9, [sp, #SG_SEQ]
	str	x9, [x19, #ST_SEQ]
Lht_pump:
	b	Lsd_pump
Lht_drop:
	mov	x0, x20
	bl	_free
	b	Lht_pump

; hls_done(stream, ok) — an HLS request ended: text read, a segment flushed (decrypted first) and timed for the bit rate, then the next.
hls_done:
	FRAME	3, 0, 1
	mov	w20, w1
	ldr	w9, [x19, #ST_REQT]
	cbz	w20, Lhd_fail
	str	wzr, [x19, #ST_ERRS]
	cmp	w9, #3
	b.eq	Lhd_seg
	b.hi	Lhd_map
	ldp	x0, x1, [x19, #ST_TXT]    ; a playlist or key: NUL-terminated
	add	x1, x1, #1
	bl	_realloc
	cbz	x0, Lhd_fail
	ldr	x9, [x19, #ST_TXTN]
	strb	wzr, [x0, x9]
	str	x0, [x19, #ST_TXT]
	mov	x0, x19
	bl	hls_text
	b	Lret3
Lhd_map:
	ldr	x0, [x19, #ST_MAPURL]     ; the init segment read
	bl	_free
	ldr	x0, [x19, #ST_RQURL]
	str	x0, [x19, #ST_MAPURL]
	str	xzr, [x19, #ST_RQURL]
	b	Lhd_next
Lhd_seg:
	ldr	w9, [x19, #ST_ENC]
	cbz	w9, 1f
	mov	x0, x19                   ; AES-128: the whole segment, decrypted, then read
	bl	seg_decrypt
1:	mov	x0, x19
	bl	seg_flush
	ldr	x9, [x19, #ST_SEQ]
	add	x9, x9, #1
	str	x9, [x19, #ST_SEQ]
	BADDR	x10, E_ST
	cmp	x19, x10
	b.ne	Lhd_next                  ; the picture's stream times the network and picks the variant
	bl	now_ns                    ; its speed, averaged into the estimate
	ldr	x9, [x19, #ST_T1]
	sub	x9, x0, x9
	cmp	x9, #1
	csinc	x9, x9, xzr, hs
	ldr	x10, [x19, #ST_GOT]
	mov	x11, #0xca00              ; 8e9: bits, per second
	movk	x11, #0xdcd6, lsl #16
	movk	x11, #1, lsl #32
	mul	x10, x10, x11
	udiv	x10, x10, x9
	ldr	x11, [x27, #E_BPS]
	cbz	x11, 2f
	add	x11, x11, x11, lsl #1
	add	x10, x10, x11
	lsr	x10, x10, #2
2:	str	x10, [x27, #E_BPS]
	ldr	x9, [x27, #E_MASTER]
	cbz	x9, Lhd_next
	bl	hls_pick                  ; the picture's variant may change at the next segment
Lhd_next:
	mov	x0, x19
	bl	st_pump
	b	Lret3
Lhd_fail:
	ldr	w9, [x19, #ST_ERRS]
	add	w9, w9, #1
	str	w9, [x19, #ST_ERRS]
	cmp	w9, #NET_TRIES
	b.hs	1f
	mov	w0, #2000                 ; again in a second
	mov	x1, x19
	bl	st_later
	b	Lret3
1:	ldr	x9, [x19, #ST_SEQ]        ; that segment is lost: on to the next
	add	x9, x9, #1
	str	x9, [x19, #ST_SEQ]
	str	wzr, [x19, #ST_ERRS]
	str	xzr, [x19, #ST_SEGOFF]
	ldp	x9, x10, [x19, #ST_TR]
	cbz	x9, 2f
	stp	wzr, wzr, [x9, #TR_FN]
2:	cbz	x10, 3f
	stp	wzr, wzr, [x10, #TR_FN]
3:	ldr	w9, [x19, #ST_REQT]
	cmp	w9, #3
	b.eq	Lhd_next
	b	Lpu_end

; seg_decrypt(stream) — decrypt the collected segment in place (AES-128-CBC, PKCS7) and read it.
seg_decrypt:
	FRAME	1, 48, 1
	ldp	x20, x9, [x19, #ST_TXT]   ; the segment and its length
	stp	xzr, xzr, [x19, #ST_TXT]
	cbz	x20, Lret1
	add	x10, sp, #32
	stp	x20, x9, [sp]             ; dataOut (in place), dataOutAvailable
	str	x10, [sp, #16]            ; dataOutMoved
	mov	w0, #1                    ; kCCDecrypt
	mov	w1, #0                    ; kCCAlgorithmAES128
	mov	w2, #1                    ; kCCOptionPKCS7Padding
	add	x3, x19, #ST_KEY
	mov	x4, #16
	add	x5, x19, #ST_IV
	mov	x6, x20
	mov	x7, x9
	CALLF	CCCrypt
	cbnz	w0, 1f
	ldr	x2, [sp, #32]
	mov	x0, x19
	mov	x1, x20
	bl	seg_bytes
1:	mov	x0, x20
	bl	_free
	b	Lret1

; txt_add(stream, bytes, length) — append to the text being collected (a playlist, a key, an encrypted segment), at most BUF_MAX.
txt_add:
	FRAME	3, 0, 1
	mov	x21, x2
	ldp	x0, x22, [x19, #ST_TXT]
	add	x1, x22, x21
	mov	x9, #BUF_MAX
	cmp	x1, x9
	b.hi	Lret3                     ; too long: cut
	bl	_realloc
	cbz	x0, Lret3
	str	x0, [x19, #ST_TXT]
	add	x0, x0, x22
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	add	x9, x22, x21
	str	x9, [x19, #ST_TXTN]
	b	Lret3

; vtt_cues(stream) — a WebVTT segment read: each cue's text, timed on the timeline by its X-TIMESTAMP-MAP, to the stream's subtitle track.
	.equ VC_BB,	8
	.equ VC_DUR,	16
	.equ VC_MEM,	24
vtt_cues:
	FRAME	4, 32
	mov	x20, x0
	ldr	x19, [x20, #ST_TR]
	ldp	x21, x22, [x20, #ST_TXT]
	stp	xzr, xzr, [x20, #ST_TXT]  ; the text is read here
	cbz	x21, Lret4
	mov	x0, x21
	add	x1, x22, #1
	bl	_realloc
	cbz	x0, Lvc_free
	mov	x21, x0
	strb	wzr, [x21, x22]
	cbz	x19, Lvc_free
	mov	x0, x21
	CSTR	x1, "MPEGTS:"
	bl	_strstr
	cbz	x0, 1f
	add	x0, x0, #7
	bl	strtol10
1:	ldr	x9, [x20, #ST_T0]
	ubfx	x9, x9, #33, #HLS_T0_BITS
	add	x9, x27, x9, lsl #3
	ldr	x9, [x9, #E_T0S]
	tbnz	x9, #63, 3f
	ldr	x9, [x27, #E_T0]
3:	sub	x23, x0, x9
	mov	x0, x21
	CSTR	x1, "LOCAL:"
	bl	_strstr
	cbz	x0, 2f
	add	x0, x0, #6
	bl	vtt_time
	mov	x9, #90
	msub	x23, x0, x9, x23
2:	mov	x24, x21
Lvc_cue:
	mov	x0, x24
	CSTR	x1, "-->"
	bl	_strstr
	cbz	x0, Lvc_free
	mov	x25, x0                   ; back to its line's start
3:	cmp	x0, x21
	b.ls	4f
	ldurb	w10, [x0, #-1]
	cmp	w10, #'\n'
	b.eq	4f
	sub	x0, x0, #1
	b	3b
4:	bl	vtt_time
	mov	x26, x0                   ; start
	add	x0, x25, #3
	bl	vtt_time
	sub	x9, x0, x26
	str	x9, [sp, #VC_DUR]
	mov	x0, x1                    ; the text: the next lines, to an empty one
	mov	w1, #'\n'
	bl	_strchr
	cbz	x0, Lvc_free
	add	x24, x0, #1
	mov	x25, x24
5:	ldrb	w10, [x25]
	cbz	w10, 7f
	cmp	w10, #'\n'
	b.ne	6f
	ldrb	w11, [x25, #1]
	cmp	w11, #'\r'
	cinc	x12, x25, eq
	ldrb	w11, [x12, #1]
	cmp	w11, #'\n'
	b.eq	7f
6:	add	x25, x25, #1
	b	5b
7:	mov	x9, x25
	cmp	x9, x24
	b.ls	8f
	ldurb	w10, [x9, #-1]
	cmp	w10, #'\r'
	cset	w10, eq
	sub	x9, x9, x10
8:	sub	x22, x9, x24              ; a tx3g sample: its length, then the text
	add	x0, x22, #2
	bl	_malloc
	cbz	x0, Lvc_free
	str	x0, [sp, #VC_MEM]
	rev16	w9, w22
	strh	w9, [x0], #2
	mov	x1, x24
	mov	x2, x22
	bl	_memcpy
	add	x9, sp, #VC_BB
	str	x9, [sp]                  ; the 9th argument
	mov	x0, #0
	ldr	x1, [sp, #VC_MEM]
	add	x2, x22, #2
	mov	x3, #0                    ; freed with it
	mov	x4, #0
	mov	x5, #0
	add	x6, x22, #2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Lvc_lost
	ldr	x0, [sp, #VC_BB]
	mov	x1, #0
	add	x2, x22, #2
	ldr	x10, [x20, #ST_SEGT]
	ldr	x11, [x27, #(E_ST + ST_SEGT)]
	cmp	x10, x11
	csel	x10, x10, x11, gt
	ldr	w11, [x20, #ST_TDUR]
	add	x10, x10, w11, uxtw #1
	sub	x4, x26, x10
	mov	x9, #90
	madd	x4, x4, x9, x23
	orr	x4, x4, #~((1 << 33) - 1)
	sdiv	x4, x4, x9
	add	x4, x4, x10
	mov	x3, x4
	ldr	x5, [sp, #VC_DUR]
	mov	w6, #1
	bl	mk_sample
	mov	x22, x0
	ldr	x0, [sp, #VC_BB]
	bl	_CFRelease
	cbz	x22, Lvc_next
	mov	x0, x22
	bl	q_push
Lvc_next:
	mov	x24, x25
	b	Lvc_cue
Lvc_lost:
	ldr	x0, [sp, #VC_MEM]
	bl	_free
Lvc_free:
	mov	x0, x21
	bl	_free
	b	Lret4

; vtt_time(text) -> x0 = the WebVTT time there ([hh:]mm:ss.ttt) in ms, x1 = past it.
vtt_time:
	FRAME	2, 16
	mov	x20, x0
	mov	x19, #0
Lvt_part:
	mov	x0, x20
	mov	x1, sp
	mov	w2, #10
	bl	_strtol
	mov	x9, #60
	madd	x19, x19, x9, x0
	ldr	x20, [sp]
	ldrb	w9, [x20]
	cmp	w9, #':'
	cinc	x20, x20, eq
	b.eq	Lvt_part
	mov	x10, #1000
	mul	x19, x19, x10
	cmp	w9, #'.'
	b.ne	1f
	add	x0, x20, #1
	mov	x1, sp
	mov	w2, #10
	bl	_strtol
	add	x19, x19, x0
	ldr	x20, [sp]
1:	mov	x0, x19
	mov	x1, x20
	b	Lret2

; seg_bytes(stream, bytes, length) — a segment's bytes to its reader: TS, boxes (fMP4), packed audio or WebVTT, as its first byte tells.
seg_bytes:
	FRAME	2, 0, 1
	mov	x21, x2
	cbz	x21, Lret2
	ldr	w9, [x19, #ST_SEGF]
	cbnz	w9, 2f
	ldrb	w10, [x20]
	mov	w9, #1
	cmp	w10, #0x47                ; TS sync
	b.eq	1f
	mov	w9, #3
	mov	w11, #0xff
	cmp	w10, #'I'                 ; ID3: packed audio
	ccmp	w10, w11, #4, ne          ; ADTS or MPEG audio
	ccmp	w10, #0x0b, #4, ne        ; AC-3
	b.eq	1f
	mov	w9, #4
	cmp	w10, #'W'                 ; WEBVTT
	b.eq	1f
	mov	w9, #2                    ; boxes
1:	str	w9, [x19, #ST_SEGF]
	cmp	w9, #3
	b.ne	2f
	mov	x0, x19                   ; packed sound: no picture
	bl	no_pic
	ldr	w9, [x19, #ST_SEGF]
2:	mov	x0, x19
	mov	x1, x20
	mov	x2, x21
	cmp	w9, #2
	b.lo	3f
	b.eq	4f
	cmp	w9, #4
	b.eq	5f
	bl	pa_feed
	b	Lret2
3:	bl	ts_feed
	b	Lret2
4:	bl	st_parse
	b	Lret2
5:	bl	txt_add                   ; WebVTT: read whole at its end
	b	Lret2

; seg_flush(stream) — a TS segment's last PES of each kind is read now.
seg_flush:
	FRAME	1, 0, 1
	ldr	w9, [x19, #ST_SEGF]
	cmp	w9, #4
	b.ne	1f
	bl	vtt_cues
	b	Lret1
1:	cmp	w9, #1
	b.ne	Lret1
	mov	x0, x19
	mov	w1, #0
	bl	pes_done
	mov	x0, x19
	mov	w1, #1
	bl	pes_done
	mov	x0, x19
	bl	vau_flush
	b	Lret1

; ts_feed(stream, bytes, length) — TS packets, whole or split across calls.
ts_feed:
	FRAME	3, 0, 1
	mov	x21, x2
Ltf_loop:
	cbz	x21, Lret3
	ldr	w9, [x19, #ST_TSN]
	cbnz	w9, Ltf_part
	cmp	x21, #188
	b.lo	Ltf_part
	ldrb	w10, [x20]
	cmp	w10, #0x47
	b.ne	Ltf_sync
	mov	x0, x19
	mov	x1, x20
	bl	ts_packet
	add	x20, x20, #188
	sub	x21, x21, #188
	b	Ltf_loop
Ltf_sync:
	add	x20, x20, #1              ; out of step: to the next sync byte
	sub	x21, x21, #1
	b	Ltf_loop
Ltf_part:
	mov	w10, #188
	sub	w22, w10, w9
	cmp	x22, x21
	csel	x22, x22, x21, lo
	add	x0, x19, #ST_TSC
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x22
	bl	_memcpy
	ldr	w9, [x19, #ST_TSN]
	add	w9, w9, w22
	str	w9, [x19, #ST_TSN]
	add	x20, x20, x22
	sub	x21, x21, x22
	cmp	w9, #188
	b.lo	Ltf_loop
	str	wzr, [x19, #ST_TSN]
	ldrb	w10, [x19, #ST_TSC]
	cmp	w10, #0x47
	b.ne	Ltf_loop
	mov	x0, x19
	add	x1, x19, #ST_TSC
	bl	ts_packet
	b	Ltf_loop

; ts_packet(stream, packet) — one 188-byte packet: the program tables, or a picture or sound PES.
ts_packet:
	FRAME	2, 0, 1
	ldrb	w9, [x20, #1]
	ldrb	w10, [x20, #2]
	and	w22, w9, #0x40            ; a unit starts here
	and	w9, w9, #0x1f
	orr	w21, w10, w9, lsl #8      ; PID
	ldrb	w9, [x20, #3]
	tbz	w9, #4, Lret2             ; no payload
	add	x1, x20, #4
	tbz	w9, #5, 1f
	ldrb	w10, [x20, #4]            ; past the adaptation field
	add	x1, x1, x10
	add	x1, x1, #1
1:	add	x9, x20, #188
	subs	x2, x9, x1
	b.ls	Lret2
	mov	x0, x19
	cbz	w21, Ltp_pat
	ldr	w9, [x19, #ST_PMT]
	cmp	w21, w9
	b.eq	Ltp_pmt
	mov	w4, w22
	ldr	w9, [x19, #ST_VPID]
	mov	w3, #0
	cmp	w21, w9
	b.eq	2f
	ldr	w9, [x19, #ST_APID]
	mov	w3, #1
	cmp	w21, w9
	b.ne	Lret2
2:	bl	pes_add
	b	Lret2
Ltp_pat:
	cbz	w22, Lret2
	bl	ts_pat
	b	Lret2
Ltp_pmt:
	cbz	w22, Lret2
	bl	ts_pmt
	b	Lret2

; ts_pat(stream, payload, length) — the program association table: the first program's map PID.
ts_pat:
	add	x13, x1, x2
	ldrb	w9, [x1]
	add	x1, x1, x9
	add	x1, x1, #1                ; the section, after the pointer field
	ldrb	w9, [x1, #1]
	ldrb	w10, [x1, #2]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x10, x1, #8
	add	x11, x1, x9
	sub	x11, x11, #1              ; less the CRC, after the 3-byte header
	cmp	x11, x13
	csel	x11, x11, x13, ls
1:	add	x12, x10, #4
	cmp	x12, x11
	b.hi	2f
	ldrh	w12, [x10]
	ldrh	w9, [x10, #2]
	add	x10, x10, #4
	cbz	w12, 1b                   ; the network PID
	rev16	w9, w9
	and	w9, w9, #0x1fff
	str	w9, [x0, #ST_PMT]
2:	ret

; ts_pmt(stream, payload, length) — the program map: the first picture (H.264, HEVC) and sound (AAC, MPEG audio, AC-3) PIDs, and their tracks.
ts_pmt:
	FRAME	3, 0, 1
	add	x20, x1, x2
	ldrb	w9, [x1]
	add	x1, x1, x9
	add	x1, x1, #1
	ldrb	w9, [x1, #1]
	ldrb	w10, [x1, #2]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x21, x1, x9
	sub	x21, x21, #1
	cmp	x21, x20
	csel	x21, x21, x20, ls
	ldrb	w9, [x1, #10]
	ldrb	w10, [x1, #11]
	and	w9, w9, #0xf
	orr	w9, w10, w9, lsl #8
	add	x22, x1, #12
	add	x22, x22, x9              ; the streams
Lpm_es:
	add	x9, x22, #5
	cmp	x9, x21
	b.hi	Lpm_end
	ldrb	w9, [x22]                 ; stream type
	ldrb	w10, [x22, #1]
	ldrb	w11, [x22, #2]
	and	w10, w10, #0x1f
	orr	w23, w11, w10, lsl #8     ; PID
	ldrb	w11, [x22, #3]
	ldrb	w12, [x22, #4]
	and	w11, w11, #0xf
	orr	w11, w12, w11, lsl #8
	add	x22, x22, #5
	add	x22, x22, x11
	mov	w24, #0
	cmp	w9, #0x1b                 ; H.264
	b.eq	Lpm_pic
	mov	w24, #1
	cmp	w9, #0x24                 ; HEVC
	b.eq	Lpm_pic
	TYPE	w24, 'a','d','t','s'      ; AudioFileStream's hint
	cmp	w9, #0x0f
	b.eq	Lpm_snd
	TYPE	w24, 'M','P','G','3'
	cmp	w9, #0x03
	ccmp	w9, #0x04, #4, ne
	b.eq	Lpm_snd
	TYPE	w24, 'a','c','-','3'
	cmp	w9, #0x81
	b.ne	Lpm_es
Lpm_snd:
	ldr	w9, [x19, #ST_APID]
	cbnz	w9, Lpm_es
	str	w23, [x19, #ST_APID]
	ldr	x9, [x19, #ST_AT]
	cbnz	x9, Lpm_es
	mov	x0, x19
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lpm_es
	str	x0, [x19, #ST_AT]
	rev	w1, w24                   ; the hint, as a four-character code
	bl	afs_open
	b	Lpm_es
Lpm_pic:
	ldr	w9, [x19, #ST_VPID]
	cbnz	w9, Lpm_es
	str	w23, [x19, #ST_VPID]
	str	w24, [x19, #ST_VHEVC]
	ldr	x9, [x19, #ST_VT]
	cbnz	x9, Lpm_es
	mov	x0, x19
	mov	w1, #'v'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	str	x0, [x19, #ST_VT]
	b	Lpm_es
Lpm_end:
	mov	x0, x19
	bl	no_pic
	b	Lret3

; pes_add(stream, data, length, sound, start) — gather a PES: the previous one is read when the next starts.
pes_add:
	FRAME	3, 0, 1
	mov	x21, x2
	mov	w22, w3
	add	x23, x19, #ST_VPES
	cbz	w22, 1f
	add	x23, x19, #ST_APES
1:	ldr	x9, [x23, #8]
	cbz	w4, 2f
	cbz	x9, 3f
	mov	x0, x19
	mov	w1, w22
	bl	pes_done
	b	3f
2:	cbz	x9, Lret3                 ; the middle of a PES whose start was missed
3:	mov	x0, x23
	mov	x1, x20
	mov	x2, x21
	bl	buf_add
	b	Lret3

; buf_add(buffer, bytes, length) — append to a {data, length, room} buffer, room grown to twice what it needs (at least 64 KiB); all dropped without memory.
buf_add:
	FRAME	3
	mov	x23, x0
	mov	x20, x1
	mov	x21, x2
	ldp	x0, x9, [x23]
	ldr	x10, [x23, #16]
	add	x24, x9, x21
	cmp	x24, x10
	b.ls	4f
	lsl	x1, x24, #1
	mov	x11, #0x10000
	cmp	x1, x11
	csel	x1, x1, x11, hs
	str	x1, [x23, #16]
	bl	_realloc
	cbz	x0, Lba_lost
	str	x0, [x23]
4:	ldp	x0, x9, [x23]
	add	x0, x0, x9
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	ldr	x9, [x23, #8]
	add	x9, x9, x21
	str	x9, [x23, #8]
	b	Lret3
Lba_lost:
	ldr	x0, [x23]
	bl	_free
	stp	xzr, xzr, [x23]
	str	xzr, [x23, #16]
	b	Lret3

; pes_done(stream, sound) — read a gathered PES: its times, anchored on the HLS timeline, then its picture or sound.
pes_done:
	FRAME	3, 0, 1
	mov	w22, w1
	add	x23, x19, #ST_VPES
	cbz	w22, 1f
	add	x23, x19, #ST_APES
1:	ldp	x20, x21, [x23]
	str	xzr, [x23, #8]
	cmp	x21, #14
	b.lo	Lret3
	ldr	w9, [x20]
	and	w9, w9, #0xffffff
	cmp	w9, #0x10000              ; 00 00 01
	b.ne	Lret3
	ldrb	w9, [x20, #7]             ; PTS, DTS flags
	ldrb	w10, [x20, #8]
	add	x24, x10, #9              ; the payload
	cmp	x24, x21
	b.hs	Lret3
	mov	x3, #-1                   ; untimed: a picture's goes on the waiting unit
	tbz	w9, #7, Lpz_cont
	add	x1, x20, #9
	bl	pts_time
	mov	x3, x4
	tbz	w9, #6, Lpz_go
	add	x1, x20, #14
	bl	pts_time
Lpz_go:
	ldr	x0, [x19, #ST_VT]
	cbz	w22, 4f
	ldr	x0, [x19, #ST_AT]
4:	cbz	x0, Lret3
	add	x1, x20, x24
	sub	x2, x21, x24
	cbnz	w22, 5f
	bl	vau_next
	b	Lret3
Lpz_cont:
	cbnz	w22, Lret3
	b	Lpz_go
5:	bl	afs_feed
	b	Lret3

pts_time:
	ldr	x10, [x1]
	rev	x10, x10
	lsr	x1, x10, #27
	bfxil	x1, x10, #26, #30
	bfxil	x1, x10, #25, #15
t33_time:
	ldr	x10, [x0, #ST_SEGT]
	mov	x11, #90
	mul	x10, x10, x11
	sub	x4, x1, x10
	ldr	x11, [x0, #ST_T0]
	tbnz	x11, #63, 2f
	orr	x11, x11, #(1 << 63)
	ubfx	x5, x11, #33, #HLS_T0_BITS
	add	x5, x27, x5, lsl #3
	ldr	x2, [x5, #E_T0S]
	ldr	w6, [x0, #ST_ENDED]
	cbnz	w6, 1f
	ldr	x2, [x27, #E_T0]
1:	eor	x6, x2, x11
	tst	x6, #~((1 << 33) - 1)
	bfxil	x11, x4, #0, #33
	csel	x11, x2, x11, eq
	str	x11, [x27, #E_T0]
	str	x11, [x0, #ST_T0]
	str	x11, [x5, #E_T0S]
2:	sub	x4, x4, x11
	sbfx	x4, x4, #0, #33
	add	x4, x4, x10
	ret

; next_sc(p, end) -> x0 = the next 00 00 01 at or after p, or end: 16 bytes at a time while none of them is zero.
next_sc:
1:	add	x9, x0, #16
	cmp	x9, x1
	b.hi	3f
	ldr	q0, [x0]
	cmeq	v0.16b, v0.16b, #0
	umaxv	b0, v0.16b
	fmov	w9, s0
	cbnz	w9, 2f
	add	x0, x0, #16
	b	1b
2:	add	x10, x0, #16              ; a zero in these 16: byte by byte
	b	4f
3:	mov	x10, x1
4:	add	x9, x0, #3
	cmp	x9, x1
	b.hi	6f
	ldrb	w9, [x0]
	cbnz	w9, 5f
	ldrb	w9, [x0, #1]
	cbnz	w9, 5f
	ldrb	w9, [x0, #2]
	cmp	w9, #1
	b.eq	7f
5:	add	x0, x0, #1
	cmp	x0, x10
	b.lo	4b
	b	1b
6:	mov	x0, x1
7:	ret

; ts_video(track, data, length, pts, dts, duration) — an access unit in Annex B: length-prefixed NAL units for the decoder, parameter sets kept for its format, a sync flag for IDR/IRAP pictures.
	.equ TV_NEXT,	8
	.equ TV_KEY,	16
	.equ TV_BB,	24
	.equ TV_LEN,	32
	.equ TV_DUR,	40
ts_video:
	FRAME	4, 48, 1
	add	x21, x1, x2
	mov	x22, x3
	mov	x23, x4
	str	x5, [sp, #TV_DUR]
	ldr	x24, [x19, #TR_ST]
	add	x0, x2, x2, lsr #1        ; start codes become 4-byte lengths
	add	x0, x0, #16
	bl	_malloc
	cbz	x0, Lret4
	mov	x25, x0
	mov	x26, x0
	str	xzr, [sp, #TV_KEY]
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	mov	x20, x0
Ltv_nal:
	cmp	x20, x21
	b.hs	Ltv_done
	add	x20, x20, #3
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	str	x0, [sp, #TV_NEXT]
1:	cmp	x0, x20                   ; its trailing zeros belong to the next start code
	b.ls	2f
	ldurb	w9, [x0, #-1]
	cbnz	w9, 2f
	sub	x0, x0, #1
	b	1b
2:	subs	x2, x0, x20
	b.eq	Ltv_skip
	ldrb	w10, [x20]
	ldr	w11, [x24, #ST_VHEVC]
	cbnz	w11, Ltv_hevc
	and	w10, w10, #0x1f
	cmp	w10, #7
	b.eq	Ltv_sps
	cmp	w10, #8
	b.eq	Ltv_pps
	cmp	w10, #9
	b.eq	Ltv_skip                  ; access unit delimiter
	cmp	w10, #5
	b.ne	Ltv_copy
	b	Ltv_iframe

Ltv_hevc:
	ubfx	w10, w10, #1, #6
	cmp	w10, #32
	b.eq	Ltv_vps
	cmp	w10, #33
	b.eq	Ltv_sps
	cmp	w10, #34
	b.eq	Ltv_pps
	cmp	w10, #35
	b.eq	Ltv_skip
	sub	w12, w10, #16
	cmp	w12, #8
	b.hs	Ltv_copy
Ltv_iframe:
	mov	w12, #1
	str	w12, [sp, #TV_KEY]
Ltv_copy:
	rev	w12, w2
	str	w12, [x26], #4
	mov	x0, x26
	mov	x1, x20
	add	x26, x26, x2
	bl	_memcpy
Ltv_skip:
	ldr	x20, [sp, #TV_NEXT]
	b	Ltv_nal
Ltv_vps:
	mov	w1, #0
	b	Ltv_ps
Ltv_sps:
	mov	w1, #1
	b	Ltv_ps
Ltv_pps:
	mov	w1, #2
Ltv_ps:
	mov	x3, x2
	mov	x2, x20
	mov	x0, x24
	bl	ps_store
	b	Ltv_skip
Ltv_done:
	sub	x9, x26, x25              ; the length-prefixed unit
	cbz	x9, Ltv_free
	str	x9, [sp, #TV_LEN]
	ldr	w9, [x24, #ST_PSNEW]
	cbz	w9, 3f
	str	wzr, [x24, #ST_PSNEW]
	mov	x0, x19
	bl	ps_format
3:	ldr	x9, [x19, #TR_FD]
	cbz	x9, Ltv_free              ; no parameter sets yet
	add	x9, sp, #TV_BB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x25
	ldr	x2, [sp, #TV_LEN]
	mov	x3, #0                    ; the default allocator frees it with the sample
	mov	x4, #0
	mov	x5, #0
	mov	x6, x2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, Ltv_free
	ldr	x0, [sp, #TV_BB]
	mov	x1, #0
	ldr	x2, [sp, #TV_LEN]
	mov	x3, x23
	mov	x4, x22
	ldr	x5, [sp, #TV_DUR]
	ldr	w6, [sp, #TV_KEY]
	bl	mk_sample
	mov	x20, x0
	ldr	x0, [sp, #TV_BB]
	bl	_CFRelease
	cbz	x20, Lret4
	mov	x0, x20
	bl	q_push
	b	Lret4
Ltv_free:
	mov	x0, x25
	bl	_free
	b	Lret4

; ---- CEA-608 captions (CC1, field 1), from H.264 SEI in presentation order, as cues of the caption track ----

; cc_avcc(bb, offset, size, pts) — a picture's NAL units (4-byte lengths): each H.264 or HEVC SEI to cc_sei.
cc_avcc:
	FRAME	3, 16
	mov	x21, x2
	mov	x22, x3
	stp	xzr, xzr, [sp]
	mov	x2, sp
	mov	x3, #0
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x9, x19, [sp]             ; contiguous bytes there, the pointer
	cmp	x9, x21
	b.lo	Lret3
	add	x20, x19, x21
1:	add	x9, x19, #5
	cmp	x9, x20
	b.hi	Lret3
	ldr	w9, [x19], #4
	rev	w9, w9
	add	x23, x19, x9              ; the next unit
	cmp	x23, x20
	b.hi	Lret3
	ldrb	w10, [x19]
	and	w11, w10, #0x1f
	cmp	w11, #6                   ; H.264 SEI: its messages after one header byte
	mov	x0, x19
	b.eq	2f
	ubfx	w11, w10, #1, #6
	cmp	w11, #39                  ; HEVC prefix SEI: after two
	b.ne	3f
	add	x0, x19, #1
2:	mov	x1, x23
	mov	x2, x22
	bl	cc_sei
3:	mov	x19, x23
	b	1b

; cc_sei(nal, end, pts) — an SEI's caption data (ATSC A/53 "GA94"), waiting for presentation order.
cc_sei:
	FRAME	2, 32
	add	x19, x0, #1
	mov	x20, x1
	mov	x21, x2
Lcs_msg:
	mov	w9, #0                    ; payload type and size: 0xff bytes add up
1:	cmp	x19, x20
	b.hs	Lret2
	ldrb	w10, [x19], #1
	add	w9, w9, w10
	cmp	w10, #0xff
	b.eq	1b
	mov	w11, #0
2:	cmp	x19, x20
	b.hs	Lret2
	ldrb	w10, [x19], #1
	add	w11, w11, w10
	cmp	w10, #0xff
	b.eq	2b
	add	x22, x19, x11             ; the next message
	cmp	x22, x20
	b.hi	Lret2
	cmp	w9, #4                    ; registered user data: B5 0031 "GA94" 03, then cc_data
	ccmp	w11, #10, #0, eq
	b.lo	3f
	ldr	x9, [x19]
	mov	x10, #0x00b5
	movk	x10, #0x4731, lsl #16
	movk	x10, #0x3941, lsl #32
	movk	x10, #0x0334, lsl #48
	cmp	x9, x10
	b.ne	3f
	ldrb	w9, [x19, #8]
	and	w9, w9, #31               ; cc_count
	add	x10, x19, #10
	mov	w12, #0
	add	x13, sp, #8
4:	cbz	w9, 5f
	add	x14, x10, #3
	cmp	x14, x22
	b.hi	5f
	ldrb	w14, [x10]
	and	w15, w14, #7
	cmp	w15, #4                   ; valid, field 1
	b.ne	6f
	cmp	w12, #8
	b.hs	6f
	ldrh	w15, [x10, #1]
	strh	w15, [x13, x12, lsl #1]
	add	w12, w12, #1
6:	add	x10, x10, #3
	sub	w9, w9, #1
	b	4b
5:	mov	x0, x21
	add	x1, sp, #8
	mov	w2, w12
	bl	cc_add
3:	mov	x19, x22
	b	Lcs_msg

; cc_add(pts, pairs, count) — into the waiting captions, by time; past four, the earliest is decoded.
cc_add:
	FRAME	3
	BADDR	x19, E_CC
	ldr	w9, [x19, #CC_QN]
	add	x10, x19, #CC_Q
	mov	w11, w9                   ; its place: after the earlier ones
1:	cbz	w11, 2f
	sub	w12, w11, #1
	add	x13, x10, x12, lsl #5
	ldr	x14, [x13]
	cmp	x14, x0
	b.le	2f
	ldp	q0, q1, [x13]             ; a later one moves up
	stp	q0, q1, [x13, #CC_E]
	mov	w11, w12
	b	1b
2:	add	x13, x10, x11, lsl #5
	str	x0, [x13]
	str	w2, [x13, #8]
	ldr	q0, [x1]
	str	q0, [x13, #16]
	add	w9, w9, #1
	str	w9, [x19, #CC_QN]
	cmp	w9, #5
	b.lo	Lret3
	mov	x20, x10                  ; the earliest, decoded
	ldr	w21, [x20, #8]
	add	x22, x20, #16
	mov	w23, #0
3:	cbz	w21, 4f
	ldrb	w0, [x22], #1
	ldrb	w1, [x22], #1
	bl	cc_pair
	orr	w23, w23, w0
	sub	w21, w21, #1
	b	3b
4:	cbz	w23, 5f
	ldr	x0, [x20]
	bl	cc_cue
5:	ldr	w9, [x19, #CC_QN]
	sub	w9, w9, #1
	str	w9, [x19, #CC_QN]
	add	x10, x19, #CC_Q
6:	cbz	w9, Lret3
	ldp	q0, q1, [x10, #CC_E]
	stp	q0, q1, [x10], #CC_E
	sub	w9, w9, #1
	b	6b

; cc_pair(b1, b2) -> w0 = 1 when the shown caption changed: a CEA-608 byte pair of CC1 (x19 = E_CC).
cc_pair:
	FRAME	2
	and	w0, w0, #0x7f
	and	w1, w1, #0x7f
	add	x20, x19, #CC_N           ; the target: loading (pop-on), or shown
	ldr	w9, [x19, #CC_MODE]
	cmp	w9, #0
	add	x9, x19, #CC_D
	csel	x20, x20, x9, eq
	cbz	w0, Lcp_no
	sub	w9, w0, #0x10
	cmp	w9, #0x10
	b.hs	Lcp_text
	orr	w9, w1, w0, lsl #8        ; a control code: the copy that follows it is dropped
	ldr	w10, [x19, #CC_LAST]
	cmp	w9, w10
	csel	w11, wzr, w9, eq
	str	w11, [x19, #CC_LAST]
	b.eq	Lcp_no
	ubfx	w10, w0, #3, #1
	str	w10, [x19, #CC_CHAN]
	cbnz	w10, Lcp_no               ; CC2's
	bic	w0, w0, #8                ; as for CC1
	cmp	w1, #0x40
	b.hs	Lcp_row                   ; a preamble: a row of its own
	cmp	w0, #0x14
	b.ne	Lcp_no                    ; styles, special and extended characters, tabs
	cmp	w1, #0x20                 ; RCL: pop-on
	b.ne	1f
	str	wzr, [x19, #CC_MODE]
	b	Lcp_no
1:	sub	w9, w1, #0x25             ; RU2-RU4: roll-up
	cmp	w9, #3
	b.hs	2f
	add	w9, w9, #2
	mov	w10, #1
	stp	w10, w9, [x19, #CC_MODE]
	b	Lcp_no
2:	cmp	w1, #0x29                 ; RDC: paint-on
	b.ne	3f
	mov	w9, #2
	str	w9, [x19, #CC_MODE]
	b	Lcp_no
3:	cmp	w1, #0x2c                 ; EDM: the shown one erased
	b.ne	4f
	str	wzr, [x19, #CC_D]
	b	Lcp_yes
4:	cmp	w1, #0x2e                 ; ENM: the loading one
	b.ne	5f
	str	wzr, [x19, #CC_N]
	b	Lcp_no
5:	cmp	w1, #0x2f                 ; EOC: the loaded one shown, the shown one loading
	b.ne	6f
	add	x9, x19, #CC_D
	mov	w10, #4
7:	ldp	q0, q1, [x9]
	ldp	q2, q3, [x9, #128]
	stp	q2, q3, [x9]
	stp	q0, q1, [x9, #128]
	add	x9, x9, #32
	subs	w10, w10, #1
	b.ne	7b
	b	Lcp_yes
6:	cmp	w1, #0x2d                 ; CR: roll-up's rows move up
	b.ne	8f
	ldr	w9, [x19, #CC_MODE]
	cmp	w9, #1
	b.ne	Lcp_no
	add	x20, x19, #CC_D
	mov	w0, #'\n'
	bl	cc_put
	add	x9, x20, #4               ; its last rows stay: the oldest lines go
	ldr	w10, [x20]
	add	x13, x9, x10
	mov	x12, x9
	mov	w14, #1
9:	cmp	x12, x13
	b.hs	10f
	ldrb	w15, [x12], #1
	cmp	w15, #'\n'
	cinc	w14, w14, eq
	b	9b
10:	ldr	w11, [x19, #CC_ROWS]
	subs	w14, w14, w11
	b.le	Lcp_yes
	mov	x12, x9
11:	ldrb	w15, [x12], #1
	cmp	w15, #'\n'
	b.ne	11b
	subs	w14, w14, #1
	b.ne	11b
	sub	x2, x13, x12
	str	w2, [x20]
	mov	x0, x9
	mov	x1, x12
	CALLF	memmove
	b	Lcp_yes
8:	cmp	w1, #0x21                 ; BS
	b.ne	Lcp_no
	ldr	w9, [x20]
	cbz	w9, Lcp_no
	sub	w9, w9, #1
	str	w9, [x20]
	b	Lcp_target
Lcp_row:
	ldr	w9, [x20]
	cbz	w9, Lcp_no
	add	x10, x20, #3
	ldrb	w10, [x10, x9]
	cmp	w10, #'\n'
	b.eq	Lcp_no
	mov	w0, #'\n'
	bl	cc_put
	b	Lcp_target
Lcp_text:
	ldr	w9, [x19, #CC_CHAN]
	cbnz	w9, Lcp_no
	mov	w21, w1
	bl	cc_put
	cmp	w21, #0x20
	b.lo	Lcp_target
	mov	w0, w21
	bl	cc_put
Lcp_target:
	add	x9, x19, #CC_D
	cmp	x20, x9
	cset	w0, eq
	b	Lret2
Lcp_yes:
	mov	w0, #1
	b	Lret2
Lcp_no:
	mov	w0, #0
	b	Lret2

; cc_put(char) — a CEA-608 character onto the target caption, as UTF-8 (x20 = it).
cc_put:
	ldr	w9, [x20]
	cmp	w9, #120
	b.hs	3f                        ; full
	add	x10, x20, #4
	adr	x11, Lcc_latin
1:	ldrb	w12, [x11], #3
	cbz	w12, 2f
	cmp	w12, w0
	b.ne	1b
	ldurh	w12, [x11, #-2]           ; a letter of its own: two UTF-8 bytes
	strh	w12, [x10, x9]
	add	w9, w9, #2
	str	w9, [x20]
	ret
2:	strb	w0, [x10, x9]
	add	w9, w9, #1
	str	w9, [x20]
3:	ret
Lcc_latin:	                          ; its code, then the UTF-8 it stands for
	.byte	0x2a, 0xc3, 0xa1, 0x5c, 0xc3, 0xa9, 0x5e, 0xc3, 0xad, 0x5f, 0xc3, 0xb3, 0x60, 0xc3, 0xba
	.byte	0x7b, 0xc3, 0xa7, 0x7c, 0xc3, 0xb7, 0x7d, 0xc3, 0x91, 0x7e, 0xc3, 0xb1, 0
	.p2align 2

; cc_cue(pts) — the shown caption from that moment, a tx3g cue of the caption track (until the next).
cc_cue:
	FRAME	3, 32
	mov	x20, x0
	BADDR	x21, (E_CC + CC_D)
	ldr	w22, [x21]
	add	x0, x22, #2
	bl	_malloc
	cbz	x0, Lret3
	mov	x23, x0
	rev16	w9, w22
	strh	w9, [x0], #2
	add	x1, x21, #4
	mov	x2, x22
	bl	_memcpy
	add	x9, sp, #8
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x23
	add	x2, x22, #2
	mov	x3, #0
	mov	x4, #0
	mov	x5, #0
	add	x6, x22, #2
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, 1f
	ldr	x19, [x27, #E_CCT]
	ldr	x0, [sp, #8]
	mov	x1, #0
	add	x2, x22, #2
	mov	x3, x20
	mov	x4, x20
	mov	x5, #(16 * 90000 & 0xffff)  ; 16 s at most
	movk	x5, #(16 * 90000 >> 16), lsl #16
	mov	w6, #1
	bl	mk_sample
	mov	x22, x0
	ldr	x0, [sp, #8]
	bl	_CFRelease
	cbz	x22, Lret3
	mov	x0, x22
	bl	q_push
	b	Lret3
1:	mov	x0, x23
	bl	_free
	b	Lret3

; vau_next(track, bytes, length, pts, dts) — a picture PES: what comes before its first start code ends the waiting access unit, which goes on; the rest waits (pts -1: all of it ends the waiting one).
vau_next:
	FRAME	4, 0, 1
	add	x21, x1, x2
	mov	x22, x3
	mov	x23, x4
	ldr	x24, [x19, #TR_ST]
	add	x24, x24, #ST_VPEN
	mov	x25, x21
	tbnz	x22, #63, 1f
	mov	x0, x20
	mov	x1, x21
	bl	next_sc
	mov	x25, x0
1:	ldr	x9, [x24, #8]
	cbz	x9, 2f                    ; nothing waits: no unit to end
	mov	x0, x24
	mov	x1, x20
	sub	x2, x25, x20
	bl	buf_add
2:	tbnz	x22, #63, Lret4
	ldr	x2, [x24, #8]
	cbz	x2, 3f
	mov	x0, x19                   ; the waiting unit, whole now: it lasts until this one's decode time
	ldr	x1, [x24]
	ldp	x3, x4, [x24, #24]
	sub	x5, x23, x4
	str	x5, [x24, #16 + 24]       ; ST_VPEN's duration slot
	bl	ts_video
3:	str	xzr, [x24, #8]
	stp	x22, x23, [x24, #24]
	mov	x0, x24
	mov	x1, x25
	sub	x2, x21, x25
	bl	buf_add
	b	Lret4

; vau_flush(stream) — the access unit waiting goes on: its segment ended.
vau_flush:
	FRAME	1
	add	x19, x0, #ST_VPEN
	ldr	x2, [x19, #8]
	ldr	x0, [x0, #ST_VT]
	cbz	x2, Lret1
	str	xzr, [x19, #8]
	cbz	x0, Lret1
	ldr	x1, [x19]
	ldp	x3, x4, [x19, #24]
	ldr	x5, [x19, #40]            ; as long as the one before
	bl	ts_video
	b	Lret1

; ps_store(stream, slot, nal, length) — keep a parameter set (VPS 0, SPS 1, PPS 2); a changed one asks for a new format.
ps_store:
	FRAME	3
	cmp	x3, #252
	b.hi	Lret3
	mov	x19, x0
	add	x20, x0, #ST_PS
	add	x20, x20, x1, lsl #8
	mov	x21, x2
	mov	x22, x3
	ldr	w9, [x20]
	cmp	w9, w22
	b.ne	1f
	add	x0, x20, #4
	mov	x1, x21
	mov	x2, x22
	bl	_memcmp
	cbz	w0, Lret3                 ; the same
1:	str	w22, [x20]
	add	x0, x20, #4
	mov	x1, x21
	mov	x2, x22
	bl	_memcpy
	mov	w9, #1
	str	w9, [x19, #ST_PSNEW]
	b	Lret3

; ps_format(track) — the picture's format from its stream's parameter sets.
ps_format:
	FRAME	1, 64, 1
	ldr	x20, [x19, #TR_ST]
	add	x9, x20, #ST_PS
	ldr	w10, [x9]
	ldr	w11, [x9, #256]
	ldr	w12, [x9, #512]
	add	x13, x9, #4
	add	x14, x9, #260
	add	x15, x9, #516
	stp	x13, x14, [sp]            ; pointers: VPS, SPS, PPS
	str	x15, [sp, #16]
	stp	x10, x11, [sp, #24]       ; and sizes
	str	x12, [sp, #40]
	cbz	w11, Lret1
	cbz	w12, Lret1
	ldr	w9, [x20, #ST_VHEVC]
	cbnz	w9, 1f
	mov	x0, #0                    ; H.264: SPS, PPS
	mov	x1, #2
	add	x2, sp, #8
	add	x3, sp, #32
	mov	w4, #4
	add	x5, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromH264ParameterSets
	b	2f
1:	cbz	w10, Lret1
	mov	x0, #0                    ; HEVC: VPS, SPS, PPS
	mov	x1, #3
	mov	x2, sp
	add	x3, sp, #24
	mov	w4, #4
	mov	x5, #0
	add	x6, sp, #48
	bl	_CMVideoFormatDescriptionCreateFromHEVCParameterSets
2:	cbnz	w0, Lret1
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 3f
	bl	_CFRelease
3:	ldr	x0, [sp, #48]
	str	x0, [x19, #TR_FD]
	bl	vid_dims
	b	Lret1

; vid_dims — the picture's shown size, its pixel aspect and clean aperture applied (x19 = track).
vid_dims:
	FRAME	0
	ldr	x0, [x19, #TR_FD]
	mov	w1, #1
	mov	w2, #1
	CALLF	CMVideoFormatDescriptionGetPresentationDimensions
	fcvtzu	w9, d0
	fcvtzu	w10, d1
	str	w9, [x19, #TR_DW]
	str	w10, [x19, #TR_DH]
	b	Lret0

; afs_file -> w0 = 1 when the mapped file is sound AudioFileStream reads (MP3, ADTS, FLAC, WAV, AIFF, CAF, AC-3): its packets fill a track's queue as it drains.
afs_file:
	FRAME	1
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Laf_no
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	mov	w9, #'a'
	mov	w10, #(90000 & 0xffff)
	movk	w10, #(90000 >> 16), lsl #16
	stp	w9, w10, [x19, #TR_KIND]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	str	x0, [x19, #TR_FQ]
	cbz	x0, Laf_no
	mov	x0, x19
	mov	w1, #0                    ; its type sniffed
	bl	afs_open
	cbnz	w0, Laf_no
1:	bl	afs_more                  ; read until it knows the format: within the first MiB
	ldr	x9, [x19, #TR_FD]
	cbnz	x9, 2f
	cbz	w0, Laf_no
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, #0x100000
	b.lo	1b
	b	Laf_no
2:	str	x19, [x27, #E_AT]
	bl	afs_dur
	mov	w0, #1
	b	Lret1
Laf_no:
	mov	w0, #0
	b	Lret1

; afs_more -> w0 = 1 while the mapped file goes on: its next 64 KiB to the track's AudioFileStream, 0 at the end or for what it cannot read (x19 = track).
afs_more:
	ldr	x0, [x27, #E_MAP]
	ldr	x1, [x27, #E_LEN]
	mov	x3, #0x10000
Lafs_win:
	FRAME	0
	ldr	x9, [x19, #TR_OFF]
	add	x2, x0, x9
	subs	x1, x1, x9
	b.ls	1f
	cmp	x1, x3
	csel	x1, x1, x3, ls
	add	x10, x9, x1
	str	x10, [x19, #TR_OFF]
	ldr	x0, [x19, #TR_AFS]
	cbz	x0, 1f
	mov	w3, #0                    ; no discontinuity flag: AudioFileStreamSeek placed it, and the flag stops WAV and AIFF
	bl	_AudioFileStreamParseBytes
	cmp	w0, #0
	cset	w0, eq
	b	Lret0
1:	mov	w0, #0
	b	Lret0

; afs_get(property, out) -> w0 = 0 when the track's AudioFileStream gave it (out: 8 bytes, zeroed first; afs_get16: 16, the first 8 zeroed) (x19 = track).
afs_get16:
	mov	w10, #16
	b	Lag_size
afs_get:
	mov	w10, #8
Lag_size:
	FRAME	0, 16
	str	xzr, [x1]
	mov	x3, x1
	mov	w1, w0
	str	w10, [sp]
	mov	x2, sp
	ldr	x0, [x19, #TR_AFS]
	bl	_AudioFileStreamGetProperty
	b	Lret0

; afs_dur — a sound file's length: its packets', else its data's at its bit rate (x19 = track).
afs_dur:
	FRAME	1, 16
	mov	w0, #(AFS_DOFF & 0xffff)
	movk	w0, #(AFS_DOFF >> 16), lsl #16
	mov	x1, sp
	bl	afs_get
	ldr	x20, [sp]                 ; the data's start
	mov	w0, #(AFS_PCNT & 0xffff)
	movk	w0, #(AFS_PCNT >> 16), lsl #16
	add	x1, sp, #8
	bl	afs_get
	ldr	x9, [sp, #8]
	ldr	w10, [x19, #TR_ASR]
	ldr	w11, [x19, #TR_AFPP]
	mov	x12, #1000
	cbz	x9, 1f
	cbz	w10, 1f
	mul	x9, x9, x11               ; packets x frames x 1000 / rate
	mul	x9, x9, x12
	udiv	x9, x9, x10
	b	2f
1:	mov	w0, #(AFS_BRAT & 0xffff)
	movk	w0, #(AFS_BRAT >> 16), lsl #16
	add	x1, sp, #8
	bl	afs_get
	ldr	x9, [x27, #E_LEN]
	ldr	x10, [x19, #TR_ST]
	cbz	x10, 4f
	ldr	x9, [x10, #ST_LEN]
4:	subs	x9, x9, x20               ; its data
	b.ls	Lret1
	ldr	w10, [sp, #8]
	cbz	w10, 3f
	mov	x12, #8000                ; bytes x 8000 / bits per second
	mul	x9, x9, x12
	udiv	x9, x9, x10
	b	2f
3:	ldr	x10, [x19, #TR_OFF]       ; no rate either: as long as the part read lasts, scaled to the whole
	subs	x10, x10, x20
	b.ls	Lret1
	ldr	x11, [x19, #TR_APTS]
	mul	x9, x9, x11
	udiv	x9, x9, x10
	mov	x10, #90
	udiv	x9, x9, x10
2:	str	x9, [x27, #E_DURMS]
	b	Lret1

; afs_seek(ms) — a sound file from the packet at that moment: AudioFileStreamSeek's byte past its data's start (x19 = track).
afs_seek:
	FRAME	1, 32
	mov	x20, x0
	bl	q_clear
	ldr	w9, [x19, #TR_ASR]
	ldr	w10, [x19, #TR_AFPP]
	mov	x1, #0
	cbz	w10, 1f
	mul	x1, x20, x9               ; the packet: ms x rate / (1000 x frames)
	mov	x11, #1000
	mul	x10, x10, x11
	udiv	x1, x1, x10
1:	str	x1, [sp, #24]
	ldr	x0, [x19, #TR_AFS]
	mov	x2, sp
	add	x3, sp, #8
	str	wzr, [sp, #8]
	CALLF	AudioFileStreamSeek
	cbnz	w0, 2f
	mov	w0, #(AFS_DOFF & 0xffff)
	movk	w0, #(AFS_DOFF >> 16), lsl #16
	add	x1, sp, #16
	bl	afs_get
	ldp	x9, x10, [sp]             ; the byte, the data's start
	ldr	x10, [sp, #16]
	add	x9, x9, x10
	str	x9, [x19, #TR_OFF]
	ldr	x9, [sp, #24]             ; that packet's time, less the priming (before 0: cut as before a target)
	ldr	w10, [x19, #TR_ASR]
	ldr	w11, [x19, #TR_AFPP]
	ldr	w12, [x19, #TR_TS]
	ldr	w13, [x19, #TR_PRIM]
	mul	x9, x9, x11
	sub	x9, x9, x13
	mul	x9, x9, x12
	sdiv	x9, x9, x10
	str	x9, [x19, #TR_APTS]
	b	Lret1
2:	str	xzr, [x19, #TR_OFF]       ; it cannot seek: from the start
	str	xzr, [x19, #TR_APTS]
	b	Lret1

; afs_stream(stream) — a web stream of sound: one track it feeds through an AudioFileStream (its type sniffed); no picture waited for.
afs_stream:
	FRAME	1, 0, 1
	mov	w9, #2
	str	w9, [x19, #ST_KIND]
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lret1
	str	xzr, [x0, #TR_APTS]
	mov	w9, #2
	str	w9, [x19, #ST_FRAG]
	str	w9, [x19, #ST_XHEAD]
	str	w9, [x0, #TR_N]
	mov	w1, #0
	bl	afs_open
	mov	x0, x19
	bl	no_pic
	b	Lret1

; no_pic(stream) — the media's first stream has no picture: the clock waits for none.
no_pic:
	BADDR	x9, E_ST
	ldr	x10, [x27, #E_VT]
	cmp	x0, x9
	ccmp	x10, #0, #0, eq
	b.ne	1f
	str	wzr, [x27, #E_WANTV]
1:	ret

; afs_open(track, hint) — the track's packets will come from an AudioFileStream; its format when the stream is ready.
afs_open:
	mov	w3, w1
	add	x4, x0, #TR_AFS
	adr	x1, afs_prop
	adr	x2, afs_pkts
	JUMPF	AudioFileStreamOpen

; afs_feed(track, bytes, length, pts) — bytes for its AudioFileStream; pts (track units, after the timeline's shift) times the packets that follow, -1 to go on.
afs_feed:
	cmn	x3, #1
	b.eq	1f
	str	x3, [x0, #TR_APTS]
1:	mov	w3, #0
	ldr	x0, [x0, #TR_AFS]
	cbz	x0, 2f
	mov	x9, x1
	mov	w1, w2
	mov	x2, x9
	b	_AudioFileStreamParseBytes
2:	ret

; afs_prop(track, stream, property, flags) — ready to produce packets: the track's format from the stream's data format and magic cookie.
	.equ AP_SIZE,	48
	.equ AP_FD,	56
	ENTRY	afs_prop
	FRAME	2, 64, 1
	mov	w9, #(AFS_READY & 0xffff)
	movk	w9, #(AFS_READY >> 16), lsl #16
	cmp	w2, w9
	b.ne	Lret2
	mov	w9, #40
	str	w9, [sp, #AP_SIZE]
	mov	x0, x20
	mov	w1, #(AFS_FORMAT & 0xffff)
	movk	w1, #(AFS_FORMAT >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	mov	x3, sp
	bl	_AudioFileStreamGetProperty
	cbnz	w0, Lret2
	mov	x21, #0                   ; its magic cookie, if it has one
	mov	x22, #0
	mov	x0, x20
	mov	w1, #(AFS_COOKIE & 0xffff)
	movk	w1, #(AFS_COOKIE >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	add	x3, sp, #AP_FD
	CALLF	AudioFileStreamGetPropertyInfo
	cbnz	w0, 1f
	ldr	w22, [sp, #AP_SIZE]
	mov	x0, x22
	bl	_malloc
	mov	x21, x0
	cbz	x0, 1f
	mov	x0, x20
	mov	w1, #(AFS_COOKIE & 0xffff)
	movk	w1, #(AFS_COOKIE >> 16), lsl #16
	add	x2, sp, #AP_SIZE
	mov	x3, x21
	bl	_AudioFileStreamGetProperty
	cmp	w0, #0
	csel	x22, x22, xzr, eq
1:	mov	x0, #0
	mov	x1, sp
	mov	x2, #0
	mov	x3, #0
	mov	x4, x22
	mov	x5, x21
	mov	x6, #0
	add	x7, sp, #AP_FD
	CALLF	CMAudioFormatDescriptionCreate
	mov	w20, w0
	mov	x0, x21
	bl	_free
	cbnz	w20, Lret2
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 2f
	bl	_CFRelease
2:	ldr	x0, [sp, #AP_FD]
	str	x0, [x19, #TR_FD]
	ldr	d0, [sp]                  ; rate and frames per packet
	fcvtzu	w9, d0
	ldr	w10, [sp, #20]
	cmp	w10, #0
	csinc	w10, w10, wzr, ne
	str	w9, [x19, #TR_ASR]
	str	w10, [x19, #TR_AFPP]
	mov	w0, #(AFS_PNFO & 0xffff)  ; the encoder's priming, if it says
	movk	w0, #(AFS_PNFO >> 16), lsl #16
	mov	x1, sp
	stp	xzr, xzr, [sp]
	bl	afs_get16
	ldr	w9, [sp, #8]
	str	w9, [x19, #TR_PRIM]
	b	Lret2

; afs_pkts(track, bytes, packets, data, descriptions) — packets found: one sound sample buffer of them, timed from TR_APTS, cut before a seek's target, queued.
	.equ AK_SB,	16
	.equ AK_BB,	24
	.equ AK_PTS,	32
	ENTRY	afs_pkts
	FRAME	3, 64, 1
	ldr	x9, [x19, #TR_FD]
	cbz	x9, Lret3
	mov	w20, w1
	mov	w21, w2
	mov	x22, x3
	mov	x23, x4
	mov	x0, x20
	bl	_malloc
	cbz	x0, Lret3
	mov	x24, x0
	mov	x1, x22
	mov	x2, x20
	bl	_memcpy
	add	x9, sp, #AK_BB
	str	x9, [sp]
	mov	x0, #0
	mov	x1, x24
	mov	x2, x20
	mov	x3, #0                    ; freed with the sample
	mov	x4, #0
	mov	x5, #0
	mov	x6, x20
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbz	w0, 1f
	mov	x0, x24
	bl	_free
	b	Lret3
1:	ldr	x22, [x19, #TR_APTS]
	ldr	w9, [x19, #TR_TS]
	orr	x9, x9, #(1 << 32)
	stp	x22, x9, [sp, #AK_PTS]
	str	xzr, [sp, #(AK_PTS + 16)]
	mov	x0, #0
	ldr	x1, [sp, #AK_BB]
	ldr	x2, [x19, #TR_FD]
	mov	x3, x21
	add	x4, sp, #AK_PTS
	mov	x5, x23
	add	x6, sp, #AK_SB
	CALLF	CMAudioSampleBufferCreateReadyWithPacketDescriptions
	mov	w24, w0
	ldr	x0, [sp, #AK_BB]
	bl	_CFRelease
	cbnz	w24, Lret3
	ldr	w9, [x19, #TR_AFPP]       ; their length: packets x frames x timescale / rate
	umull	x9, w9, w21
	ldr	w10, [x19, #TR_TS]
	ldr	x11, [x19, #TR_AREM]
	madd	x9, x9, x10, x11
	ldr	w10, [x19, #TR_ASR]
	cmp	w10, #0
	csinc	w10, w10, wzr, ne
	udiv	x23, x9, x10
	msub	x11, x23, x10, x9
	str	x11, [x19, #TR_AREM]
	add	x9, x22, x23
	str	x9, [x19, #TR_APTS]
	str	x22, [x19, #TR_LAST]
	ldr	x9, [x19, #TR_TGT]
	subs	x1, x9, x22
	b.le	2f
	ldr	x0, [sp, #AK_SB]          ; before the target: decoded, cut
	mov	x2, x23
	bl	trim
2:	ldr	x0, [sp, #AK_SB]
	bl	q_push
	b	Lret3

; trim(sample, amount, duration) — the sound sample's first min(amount, duration) is decoded, not heard (x19 = track).
trim:
	FRAME	2, 32
	mov	x20, x0
	cmp	x1, x2
	csel	x1, x1, x2, lo
	ldr	w9, [x19, #TR_TS]
	orr	x9, x9, #(1 << 32)
	stp	x1, x9, [sp]
	str	xzr, [sp, #16]
	mov	x0, sp
	mov	x1, #0
	CALLF	CMTimeCopyAsDictionary
	mov	x21, x0
	mov	x0, x20
	ldr	x1, [x27, #F_kCMSampleBufferAttachmentKey_TrimDurationAtStart]
	ldr	x1, [x1]
	mov	x2, x21
	mov	w3, #1                    ; kCMAttachmentMode_ShouldPropagate
	CALLF	CMSetAttachment
	mov	x0, x21
	bl	_CFRelease
	b	Lret2

; pa_feed(stream, bytes, length) — packed audio (AAC, MPEG audio, AC-3 frames): each segment's ID3 tag times its first frame.
pa_feed:
	FRAME	3, 0, 1
	mov	x21, x2
	mov	x23, #-1                  ; no time: the packets go on
	ldr	x9, [x19, #ST_GOT]
	ldr	x10, [x19, #ST_SEGOFF]
	cmp	x9, x21
	ccmp	x10, #0, #0, eq
	b.ne	Lpa_feed                  ; not the segment's first bytes
	ldrb	w9, [x20]
	cmp	w9, #'I'
	b.ne	Lpa_track
	mov	x0, x20
	mov	x1, x21
	bl	id3_pts
	cmp	x0, x21
	csel	x0, x0, x21, lo
	add	x20, x20, x0              ; past the tag
	sub	x21, x21, x0
	tbnz	x1, #63, Lpa_track
	mov	x0, x19
	bl	t33_time
	mov	x23, x4
Lpa_track:
	ldr	x22, [x19, #ST_AT]
	cbnz	x22, Lpa_feed
	cbz	x21, Lret3
	mov	x0, x19                   ; the first segment: a sound track, its stream hinted by the first frame's sync
	mov	w1, #'a'
	mov	w2, #(90000 & 0xffff)
	movk	w2, #(90000 >> 16), lsl #16
	bl	trk_new
	cbz	x0, Lret3
	mov	x22, x0
	str	x22, [x19, #ST_AT]
	ldrb	w9, [x20]
	TYPE	w1, 'a','c','-','3'       ; 0x0b 0x77: AC-3
	cmp	w9, #0x0b
	b.eq	2f
	TYPE	w1, 'M','P','G','3'       ; MPEG audio
	ldrb	w9, [x20, #1]
	mov	w10, #0xf6
	and	w9, w9, w10
	cmp	w9, #0xf0
	b.ne	2f
	TYPE	w1, 'a','d','t','s'       ; ADTS
2:	rev	w1, w1                    ; a four-character code
	mov	x0, x22
	bl	afs_open
Lpa_feed:
	ldr	x0, [x19, #ST_AT]
	cbz	x0, Lret3
	ldr	x9, [x0, #TR_APTS]        ; no time stamp and none yet (a start or a seek): its segment's start
	and	x9, x9, x23
	cmn	x9, #1
	b.ne	3f
	ldr	x23, [x19, #ST_SEGT]
	mov	x9, #90
	mul	x23, x23, x9
3:	mov	x1, x20
	mov	x2, x21
	mov	x3, x23
	bl	afs_feed
	b	Lret3

; id3_pts(data, length) -> x0 = an ID3 tag's length, x1 = its Apple transport stream time stamp (90 kHz), or -1.
id3_pts:
	FRAME	2, 0, 1
	mov	x21, #-1
	mov	x22, #0
	cmp	x20, #10
	b.lo	3f
	ldrb	w9, [x19, #6]             ; size: four 7-bit bytes, after the 10-byte header
	ldrb	w10, [x19, #7]
	ldrb	w11, [x19, #8]
	ldrb	w12, [x19, #9]
	orr	w12, w12, w11, lsl #7
	orr	w12, w12, w10, lsl #14
	orr	w12, w12, w9, lsl #21
	add	x22, x12, #10
	cmp	x22, x20
	csel	x20, x22, x20, lo
	add	x20, x19, x20             ; where the frames end
	add	x19, x19, #10
1:	add	x9, x19, #63
	cmp	x9, x20
	b.hi	3f
	ldr	w9, [x19]
	ldr	w10, [x19, #4]
	rev	w10, w10                  ; the frame's size
	TYPE	w11, 'P','R','I','V'
	cmp	w9, w11
	b.ne	2f
	add	x0, x19, #10
	CSTR	x1, "com.apple.streaming.transportStreamTimestamp"
	mov	x2, #45
	bl	_strncmp
	cbnz	w0, 2f
	ldur	x21, [x19, #55]
	rev	x21, x21
	and	x21, x21, #0x1ffffffff
	b	3f
2:	add	x19, x19, #10
	add	x19, x19, x10
	b	1b
3:	mov	x0, x22
	mov	x1, x21
	b	Lret2

; ---- Engine: This Mac's own player. Sample tables are read in place from the mapped file; CoreMedia's renderers decode, show and play on one clock ----

; The blocks the renderers call for more media: global, so their state is B's.
	.pushsection __DATA,__data
	.p2align 3
Lblk_v:	.quad	0                         ; isa: _NSConcreteGlobalBlock, set by main
	.long	0x50000000                ; global, with a signature
	.long	0
	.quad	feed_v
	.quad	Lblk_desc
Lblk_a:	.quad	0
	.long	0x50000000
	.long	0
	.quad	feed_a
	.quad	Lblk_desc
Lblk_s:	.quad	0
	.long	0x50000000
	.long	0
	.quad	sub_tick
	.quad	Lblk_desc
Lblk_desc:	.quad	0, 32, Lblk_sig
	.popsection
	.pushsection __DATA,__data
Lblk_sig:	.asciz	"v8@?0"
	.popsection

; unmap_cb(refcon, memory, size) — a released file mapping.
	ENTRY	unmap_cb
	mov	x0, x1
	mov	x1, x2
	b	_munmap

; av1_check — AV1 streams only where the chip decodes them: asked off the launch path, as the answer makes a decoder (~20 ms).
	VMENTRY	av1_check, Lp_av1
	.pushsection __DATA,__data
Lp_av1:
	CALL	F_VTIsHardwareDecodeSupported, ">X"
	.long	0x61763031                ; 'av01'
	ANDH	0xff
	SW	G_AV1
	OP_END
	.popsection

; eng_cmd(work, context) — run work(context) on the media queue.
eng_cmd:
	mov	x2, x0
	ldr	x0, [x28, #G_MEDIAQ]
	b	_dispatch_async_f

; eng_init — the synchronizer and its two renderers, made on the media queue: the first costs ~45 ms of framework setup, off the launch path.
	VMENTRY	eng_init, Lp_init
	.pushsection __DATA,__data
Lp_init:
	CLS	AVSampleBufferRenderSynchronizer
	MSG	S_new, "="
	STE	E_SYNC
	CLS	AVSampleBufferAudioRenderer
	MSG	S_new, "="
	STE	E_AR
	MSG	S_setAudioTimePitchAlgorithm_, "S" ; speed changes keep the pitch
	.asciz	"Spectral"
	LDE	E_SYNC
	MSG	S_addRenderer_, "E"
	.short	E_AR
	NCALL	snd_watch
	CLS	AVSampleBufferDisplayLayer
	MSG	S_new, "="
	STO	G_SBLAYER
	MSG	S_setVideoGravity_, "S"   ; pic_layout gives it the picture's shape
	.asciz	"AVLayerVideoGravityResize"
	MSG	S_sampleBufferRenderer, "="
	STE	E_VR
	LDE	E_SYNC
	MSG	S_addRenderer_, "E"
	.short	E_VR
	NCALL	Leng_vol
	CLS	NSOperationQueue          ; the session calls its delegate on the media queue
	MSG	S_new, "="
	SL	0
	MSG	S_setUnderlyingQueue_, "O"
	.byte	G_MEDIAQ >> 3
	CLS	NSURLSessionConfiguration
	MSG	S_defaultSessionConfiguration, "="
	SL	1
	CLS	NSURLSession
	MSG	S_sessionWithConfiguration_delegate_delegateQueue_, "=bOa"
	.byte	G_CTRL >> 3
	MSG	S_retain, "="
	STE	E_SESSION
	LEA	Lvt_sps                   ; VideoToolbox's H.264 and HEVC decoders loaded off the launch path: a first picture ~60 ms sooner
	STE	B_VTW
	LEA	Lvt_pps
	STE	B_VTW + 8
	IMM	Lvt_pps - Lvt_sps
	STE	B_VTW + 24
	IMM	Lvt_vps - Lvt_pps
	STE	B_VTW + 32
	CALL	F_CMVideoFormatDescriptionCreateFromH264ParameterSets, ">IIBBIB"
	.byte	0, 2
	.short	B_VTW, B_VTW + 24
	.byte	4
	.short	B_VTW + 48
	NCALL	vt_warm, "V"
	LEA	Lvt_vps
	STE	B_VTW
	LEA	Lvt_hsps
	STE	B_VTW + 8
	LEA	Lvt_hpps
	STE	B_VTW + 16
	IMM	Lvt_hsps - Lvt_vps
	STE	B_VTW + 24
	IMM	Lvt_hpps - Lvt_hsps
	STE	B_VTW + 32
	IMM	Lvt_end - Lvt_hpps
	STE	B_VTW + 40
	CALL	F_CMVideoFormatDescriptionCreateFromHEVCParameterSets, ">IIBBIIB"
	.byte	0, 3
	.short	B_VTW, B_VTW + 24
	.byte	4, 0
	.short	B_VTW + 48
	NCALL	vt_warm, "V"
	NCALL	post_main, "PI"
	.long	ui_attach - Lvm_base
	.byte	0
	OP_END
Lvt_sps:	.byte	0x67, 0x42, 0xc0, 0x0a, 0xd9, 0x07, 0x3c, 0xc0, 0x44, 0x00, 0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x08, 0x3c, 0x48, 0x99, 0x20
Lvt_pps:	.byte	0x68, 0xcb, 0x83, 0xcb, 0x20
Lvt_vps:	.byte	0x40, 0x01, 0x0c, 0x01, 0xff, 0xff, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0xb0, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x99, 0x15, 0xc0, 0x90
Lvt_hsps:	.byte	0x42, 0x01, 0x01, 0x01, 0x60, 0x00, 0x00, 0x03, 0x00, 0xb0, 0x00, 0x00, 0x03, 0x00, 0x00, 0x03, 0x00, 0x99, 0xa0, 0x01, 0xe0, 0x20, 0x02, 0x1c, 0x58, 0x81, 0x5e, 0xe4, 0x59, 0x51
Lvt_hpps:	.byte	0x44, 0x01, 0xc0, 0x2c, 0xbc, 0x14, 0xc9
Lvt_end:
	.popsection

; vt_warm(status) — after a format was made in B_VTW + 48 (status 0): a decompression session for it made and dropped, so VideoToolbox's decoder is loaded early; the format released.
vt_warm:
	VM	Lp_vtwarm
	.pushsection __DATA,__data
Lp_vtwarm:
	GL	0
	JNZ	Lp_vtwarm_end
	CALL	F_VTDecompressionSessionCreate, ">IEIIIB"
	.byte	0
	.short	B_VTW + 48
	.byte	0, 0, 0
	.short	B_VTW + 56
	JNZ	Lp_vtwarm_fd
	LDE	B_VTW + 56
	CALL	F_VTDecompressionSessionInvalidate, "V"
	LDE	B_VTW + 56
	CALL	F_CFRelease, "V"
	HERE	Lp_vtwarm_fd
	LDE	B_VTW + 48
	CALL	F_CFRelease, "V"
	HERE	Lp_vtwarm_end
	OP_END
	.popsection

; ui_attach — the engine's layer goes into its view.
	ENTRY	ui_attach
	FRAME	0
	ADDR	x0, Lprog_attach
	bl	ui_run
	bl	pic_layout
	b	Lret0

; ui_poll — re-render now.
	ENTRY	ui_poll
	b	local_poll

; eng_close — stop and forget the open file; its mapping goes once the renderers let go of its samples.
	VMENTRY	eng_close, Lp_close
	.pushsection __DATA,__data
Lp_close:
	LDE	E_SYNC
	MSG	S_setRate_, "D"
	.short	0
	LDE	E_VR
	MSG	S_stopRequestingMediaData
	LDE	E_VR
	MSG	S_flushWithRemovalOfDisplayedImage_completionHandler_, "II" ; the last picture goes too
	.byte	1, 0
	LDE	E_AR
	MSG	S_stopRequestingMediaData
	LDE	E_AR
	MSG	S_flush
	NCALL	sub_reset
	NCALL	st_close, "B"
	.short	E_ST
	NCALL	st_close, "B"
	.short	E_ST + ST_SIZE
	NCALL	st_close, "B"
	.short	E_ST + 2 * ST_SIZE
	LDE	E_MASTER
	CALL	F_free, "V"
	LDE	E_MURL
	CALL	F_free, "V"
	NCALL	eng_frees
	NCALL	sub_obs
	OP_END
	.popsection

; eng_frees — the tracks' formats, sound parsers and queues go, the mapping's block is let go, the engine's state cleared.
eng_frees:
	FRAME	1
	BADDR	x19, E_TR
	add	x20, x19, #((TRACKS * TR_SIZE) >> 12), lsl #12
Lec_fd:
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 1f
	bl	_CFRelease
1:	ldr	x0, [x19, #TR_AFS]
	cbz	x0, 2f
	CALLF	AudioFileStreamClose
2:	bl	q_clear
	ldr	x0, [x19, #TR_FQ]
	bl	_free
	ldr	x0, [x19, #TR_FL]
	bl	_free
	add	x19, x19, #TR_SIZE
	cmp	x19, x20
	b.lo	Lec_fd
	ldr	x0, [x27, #E_PARENT]
	cbz	x0, 1f
	bl	_CFRelease
1:	BADDR	x0, E_CLR
	mov	x1, #E_CLRN
	bl	_bzero
	b	Lret1

; eng_open(request) — play a file on This Mac from its start; request = {play generation, path}, freed here. What it cannot read, AVPlayer gets (eng_fallback).
	ENTRY	eng_open
	FRAME	2, 176, 1	; the 9th argument at sp, struct stat at sp + 16
	bl	eng_close
	add	x0, x19, #8
	mov	w1, #0                    ; O_RDONLY
	CALLF	open
	mov	w20, w0
	tbnz	w0, #31, Leo_fail
	add	x1, sp, #16
	CALLF	fstat
	ldr	x21, [sp, #(16 + STAT_SIZE)]
	cbnz	w0, Leo_close
	mov	x0, #0
	mov	x1, x21
	mov	w2, #PROT_READ
	mov	w3, #MAP_PRIVATE
	mov	w4, w20
	mov	x5, #0
	CALLF	mmap
	mov	x22, x0
	mov	w0, w20
	bl	_close
	cmn	x22, #1
	b.eq	Leo_fail                  ; MAP_FAILED, e.g. an empty file
	str	x22, [x27, #E_MAP]
	str	x21, [x27, #E_LEN]
	mov	x0, x22
	mov	x1, x21
	mov	w2, #MADV_SEQUENTIAL
	CALLF	madvise
	BADDR	x9, E_PARENT
	str	x9, [sp]
	stp	xzr, xzr, [sp, #16]       ; CMBlockBufferCustomBlockSource, packed to 4 (CoreMedia copies it): the mapping goes with the last sample
	adr	x9, unmap_cb
	stur	x9, [sp, #(16 + 12)]      ; FreeBlock
	stur	xzr, [sp, #(16 + 20)]     ; refCon
	mov	x0, #0
	mov	x1, x22
	mov	x2, x21
	mov	x3, #0
	add	x4, sp, #16
	mov	x5, #0
	mov	x6, x21
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbz	w0, Leo_read
	mov	x0, x22                   ; no buffer to own it: unmap here
	mov	x1, x21
	bl	_munmap
	b	Leo_fail
Leo_read:
	bl	mp4_open
	cbnz	w0, 1f
	bl	mkv_open
	cbnz	w0, 1f
	bl	flv_open
	cbnz	w0, 1f
	bl	afs_file                  ; none: a sound file AudioFileStream reads
	cbnz	w0, 1f
	ldr	w9, [x27, #E_M4A]
	cmp	w9, #1
	b.ne	Leo_fail
	BADDR	x20, E_TR                 ; an M4A it could not read (its index last): its track goes, the boxes are read instead
	ldr	x0, [x20, #TR_AFS]
	CALLF	AudioFileStreamClose
	ldr	x0, [x20, #TR_FQ]
	bl	_free
	mov	x0, x20
	mov	x1, #TR_SIZE
	bl	_bzero
	mov	w9, #2
	str	w9, [x27, #E_M4A]
	str	wzr, [x27, #E_NTR]
	b	Leo_read
1:	ldr	w0, [x19]
	str	w0, [x27, #E_GEN]
	ldr	x9, [x27, #E_VT]
	cmp	x9, #0
	cset	w9, ne
	str	w9, [x27, #E_WANTV]
	bl	tick_later                ; its ticks
	mov	x0, x19
	bl	_free
	mov	x0, #0
	bl	eng_seek                 ; from the start
	adr	x0, ui_poll
	mov	x1, #0
	bl	post_main
	b	Lret2
Leo_close:
	mov	w0, w20
	bl	_close
Leo_fail:
	bl	eng_close
	ldr	w20, [x19]
	mov	x0, x19
	bl	_free
	adr	x0, eng_fallback
	mov	x1, x20
	bl	post_main
	b	Lret2

; eng_fallback(generation) — the engine cannot play This Mac's file: AVPlayer tries it, unless a newer play came (main).
	VMTENTRY	eng_fallback
	LW	G_PLAYGEN
	EQL	0
	JZ	Lp_fallback_end
	IMM	1
	SW	G_MODE
	NCALL	eng_cmd, "PI"
	.long	eng_close - Lvm_base
	.byte	0
	LDE	B_LTPATH
	ANDH	255
	EQ	'/'
	JNZ	Lp_fallback_file
	NCALL	mkurl, "=B"               ; web media
	.short	B_LTPATH
	JMP	Lp_fallback_item
	HERE	Lp_fallback_file
	NCALL	mkstr, "=B"
	.short	B_LTPATH
	SL	1
	CLS	NSURL
	MSG	S_fileURLWithPath_, "=b"
	HERE	Lp_fallback_item
	SL	1
	CLS	AVPlayerItem
	MSG	S_playerItemWithURL_, "=b"
	SL	1
	LD	G_PLAYER
	MSG	S_replaceCurrentItemWithPlayerItem_, "b"
	LD	G_PLAYER
	MSG	S_play
	NCALL	local_poll
	HERE	Lp_fallback_end
	OP_END
	.p2align 2

; mp4_open() -> w0 = 1 when the mapped file is an MP4 or QuickTime movie with a picture or sound CoreMedia knows: its tracks are read and the first of each kind plays.
mp4_open:
	FRAME	4
	ldr	x19, [x27, #E_MAP]
	ldr	x9, [x27, #E_LEN]
	add	x20, x19, x9
	mov	x0, x19
	mov	x1, x20
	TYPE	w2, 'f','t','y','p'
	bl	box_find
	cbz	x0, Lmo_moov              ; none: QuickTime
	add	x9, x0, #4
	cmp	x9, x1
	b.hi	Lmo_moov
	ldr	w9, [x0]                  ; the major brand
	TYPE	w10, 'q','t',' ',' '
	cmp	w9, w10
	cset	w9, ne
	str	w9, [x27, #E_ISO]
	ldr	w9, [x0]
	TYPE	w10, 'M','4','A',' '
	ldr	w11, [x27, #E_M4A]
	cmp	w9, w10
	ccmp	w11, #0, #0, eq
	b.eq	Lmo_m4a
Lmo_moov:
	mov	x0, x19
	mov	x1, x20
	TYPE	w2, 'm','o','o','v'
	bl	box_find
	cbz	x0, Lnil4
	b	Lmo_go
Lmo_m4a:
	mov	w9, #1                    ; sound alone: AudioFileStream packs its packets (one per sample costs the renderer more)
	str	w9, [x27, #E_M4A]
	b	Lnil4
Lmo_go:
	mov	x21, x0
	mov	x22, x1
	TYPE	w2, 'm','v','h','d'
	bl	box_find
	cbz	x0, Lnil4
	bl	mvhd_read
	cbz	w10, Lnil4
	mov	x12, #1000
	mul	x11, x11, x12
	udiv	x11, x11, x10
	str	x11, [x27, #E_DURMS]
	mov	x23, x21
Lmo_trak:
	mov	x0, x23
	mov	x1, x22
	TYPE	w2, 't','r','a','k'
	bl	box_find
	cbz	x0, Lmo_pick
	mov	x23, x1                   ; the next one starts after it
	mov	w2, #0
	mov	x3, #0
	bl	trak_open
	b	Lmo_trak
Lmo_pick:
	BADDR	x9, E_TR
	add	x10, x9, #((TRACKS * TR_SIZE) >> 12), lsl #12
Lmo_each:
	ldr	w11, [x9, #TR_KIND]
	cmp	w11, #'v'
	b.ne	1f
	ldr	x12, [x27, #E_VT]
	cbnz	x12, 1f
	str	x9, [x27, #E_VT]
1:	cmp	w11, #'a'
	b.ne	2f
	ldr	x12, [x27, #E_AT]
	cbnz	x12, 2f
	str	x9, [x27, #E_AT]
2:	add	x9, x9, #TR_SIZE
	cmp	x9, x10
	b.lo	Lmo_each
	ldr	x9, [x27, #E_VT]
	ldr	x0, [x27, #E_AT]
	cbnz	x9, 3f
	cbz	x0, 3f
	bl	snd_fd                    ; no picture: the sound's format now, so one CoreMedia cannot read falls back
	cbnz	x0, 3f
	str	xzr, [x27, #E_AT]
3:	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cmp	x9, #0
	cset	w0, ne
	b	Lret4

; snd_fd(track) -> x0 = its sound format, from its sample description the first time; 0 if CoreMedia cannot read it. A file's is made as it first plays: the first one costs ~12 ms, after the picture's first samples.
snd_fd:
	FRAME	1, 0, 1
	ldr	x0, [x19, #TR_FD]
	cbnz	x0, Lret1
	ldr	x1, [x19, #TR_STSD]
	ldr	w2, [x19, #TR_STSDN]
	cbz	w2, Lsf_own
	mov	x3, #0                    ; QuickTime
	ldr	w9, [x27, #E_ISO]
	cbz	w9, 1f
	ldr	x3, [x27, #F_kCMSoundDescriptionFlavor_ISOFamily]
	ldr	x3, [x3]
1:	add	x4, x19, #TR_FD
	CALLF	CMAudioFormatDescriptionCreateFromBigEndianSoundDescriptionData
	ldr	x0, [x19, #TR_FD]
	b	Lret1
Lsf_own:
	cbz	x1, Lret1                 ; snd_keep's: a format, the cookie's length, the cookie
	mov	x0, #0
	ldr	w4, [x1, #40]
	add	x5, x1, #44
	mov	x2, #0
	mov	x3, #0
	mov	x6, #0
	add	x7, x19, #TR_FD
	CALLF	CMAudioFormatDescriptionCreate
	ldr	x0, [x19, #TR_FD]
	b	Lret1
box_v1:
	add	x9, x0, #24
	cmp	x9, x1
	b.hi	2f
	ldrb	w9, [x0]
	ldr	w10, [x0, #12]
	cbz	w9, 1f
	ldr	w10, [x0, #20]
1:	rev	w10, w10
2:	ret

; trak_open(trak, end, fragmented, track) -> x0 = the track (the next free one if 0), read: kind, timescale, edit, tables (empty when fragmented) and format; 0 for one this player cannot use.
trak_open:
	FRAME	4
	mov	x20, x0
	mov	x21, x1
	mov	w26, w2
	mov	x19, x3
	cbnz	x19, 1f
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lnil4
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9      ; TR_SIZE
1:	TYPE	w2, 't','k','h','d'
	bl	box_find
	cbz	x0, Lnil4
	bl	box_v1
	b.hi	Lnil4
	str	w10, [x19, #TR_ID]
	add	x11, x0, #40              ; its matrix's first column: the turn
	cbz	w9, 2f
	add	x11, x0, #52
2:	add	x12, x11, #8
	cmp	x12, x1
	b.hi	3f
	ldp	w12, w13, [x11]
	rev	w12, w12                  ; cos
	rev	w13, w13                  ; sin, with y down
	cmp	w13, #0
	mov	w14, #-90
	csel	w14, w14, wzr, gt
	mov	w15, #90
	csel	w14, w15, w14, lt
	cmp	w12, #0
	mov	w15, #180
	csel	w14, w15, w14, lt
	str	w14, [x19, #TR_ROT]
3:	mov	x0, x20
	mov	x1, x21
	TYPE	w2, 'm','d','i','a'
	bl	box_find
	cbz	x0, Lnil4
	mov	x22, x0
	mov	x23, x1
	TYPE	w2, 'h','d','l','r'
	bl	box_find
	cbz	x0, Lnil4
	add	x9, x0, #12
	cmp	x9, x1
	b.hi	Lnil4
	ldr	w24, [x0, #8]             ; the handler: 'vide', 'soun', ...
	mov	x0, x22
	mov	x1, x23
	TYPE	w2, 'm','d','h','d'
	bl	box_find
	cbz	x0, Lnil4
	bl	box_v1
	b.hi	Lnil4
	cbz	w10, Lnil4
	str	w10, [x19, #TR_TS]
	add	x11, x0, #20              ; its language: three letters, 5 bits each
	cbz	w9, 2f
	add	x11, x0, #32
2:	add	x12, x11, #2
	cmp	x12, x1
	b.hi	3f
	ldrh	w12, [x11]
	rev16	w12, w12
	cmp	w12, #0x400               ; below: a QuickTime language number
	b.lo	3f
	ubfx	w13, w12, #10, #5
	ubfx	w14, w12, #5, #5
	and	w15, w12, #31
	add	w13, w13, #0x60
	add	w14, w14, #0x60
	add	w15, w15, #0x60
	orr	w13, w13, w14, lsl #8
	orr	w13, w13, w15, lsl #16
	TYPE	w14, 'u','n','d',0
	cmp	w13, w14
	csel	w13, w13, wzr, ne         ; "und": none
	str	w13, [x19, #TR_LANG]
3:	mov	x0, x22
	mov	x1, x23
	TYPE	w2, 'm','i','n','f'
	bl	box_find
	cbz	x0, Lnil4
	TYPE	w2, 's','t','b','l'
	bl	box_find
	cbz	x0, Lnil4
	mov	x22, x0
	mov	x23, x1
	TYPE	w2, 's','t','s','d'
	bl	box_find
	cbz	x0, Lnil4
	add	x9, x0, #12
	cmp	x9, x1
	b.hi	Lnil4
	ldr	w10, [x0, #8]
	rev	w10, w10                  ; the first description's size
	sub	x11, x1, x0
	sub	x11, x11, #8
	cmp	x10, #16
	ccmp	x10, x11, #2, hs
	b.hi	Lnil4
	add	x0, x0, #8
	str	x0, [x19, #TR_STSD]
	str	w10, [x19, #TR_STSDN]
	adr	x25, Lstbl
Lto_tbl:
	ldr	w2, [x25]
	cbz	w2, Lto_tables
	mov	x0, x22
	mov	x1, x23
	bl	box_find
	cbz	x0, Lto_next
	ldrb	w9, [x25, #6]
	ldrb	w10, [x25, #7]
	add	x11, x0, x9
	ldur	w12, [x11, #-4]
	rev	w12, w12                  ; entries
	tbz	w10, #7, 1f
	ldr	w13, [x0, #4]
	cmp	w13, #0
	csel	w10, w10, wzr, eq         ; a fixed size: no table
1:	and	w10, w10, #0x7f
	umaddl	x11, w12, w10, x11
	cmp	x11, x1
	b.hi	Lnil4                     ; cut short: not a track to trust
	ldrb	w9, [x25, #4]
	str	x0, [x19, x9]
	ldrb	w9, [x25, #5]
	str	w12, [x19, x9]
Lto_next:
	add	x25, x25, #8
	b	Lto_tbl
Lto_tables:
	ldr	x9, [x19, #TR_STSZ]
	cbz	x9, Lnil4
	ldr	w10, [x9, #4]
	rev	w10, w10
	str	w10, [x19, #TR_FIXED]
	cbnz	w26, Lto_edit             ; fragmented: samples come later
	ldr	w9, [x19, #TR_N]
	ldr	w10, [x19, #TR_NST]
	ldp	w11, w12, [x19, #TR_NSC]
	cmp	w9, #0
	ccmp	w10, #0, #4, ne
	ccmp	w11, #0, #4, ne
	ccmp	w12, #0, #4, ne
	b.eq	Lnil4                     ; no samples, or a table missing
Lto_edit:
	mov	x0, x20
	mov	x1, x21
	TYPE	w2, 'e','d','t','s'
	bl	box_find
	cbz	x0, Lto_fmt
	TYPE	w2, 'e','l','s','t'
	bl	box_find
	cbz	x0, Lto_fmt
	bl	elst_shift
Lto_fmt:
	ldr	x0, [x19, #TR_FD]         ; a track read again lets its old format go
	str	xzr, [x19, #TR_FD]
	cbz	x0, 1f
	bl	_CFRelease
1:	mov	x0, #0
	ldr	x1, [x19, #TR_STSD]
	ldr	w2, [x19, #TR_STSDN]
	ldr	w9, [x27, #E_ISO]
	TYPE	w10, 'v','i','d','e'
	cmp	w24, w10
	b.eq	Lto_vide
	TYPE	w10, 's','o','u','n'
	cmp	w24, w10
	b.ne	Lto_text
	ldr	w9, [x27, #E_NET]
	cbz	w9, Lto_snd               ; a file's sound format comes when it first plays (snd_fd)
	mov	x0, x19
	bl	snd_fd
	cmp	x0, #0
	cset	w0, eq
	mov	w9, #'a'
	b	Lto_kind
Lto_snd:
	mov	w0, #0
	mov	w9, #'a'
	b	Lto_kind
Lto_vide:
	mov	w3, #0                    ; the compressor name's text encoding
	mov	x4, #0
	cbz	w9, 1f
	ldr	x4, [x27, #F_kCMImageDescriptionFlavor_ISOFamily]
	ldr	x4, [x4]
1:	add	x5, x19, #TR_FD
	CALLF	CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData
	cbnz	w0, Lnil4
	bl	vid_dims
	mov	w0, #0
	mov	w9, #'v'
Lto_kind:
	cbnz	w0, Lnil4                 ; a format CoreMedia does not know
	str	w9, [x19, #TR_KIND]
	mov	x0, x19
	b	Lret4
Lto_text:
	ldr	w3, [x1, #4]              ; subtitles or captions, known by their sample description
	adr	x10, Ltext
1:	ldr	w11, [x10], #4
	cbz	w11, Lnil4
	cmp	w3, w11
	b.ne	1b
	rev	w1, w3
	mov	w2, w1
	mov	x3, #0
	add	x4, x19, #TR_FD
	bl	_CMFormatDescriptionCreate
	mov	w9, #'s'
	b	Lto_kind
Ltext:	.ascii	"tx3gtextwvttc608"
	.long	0
	.p2align 2
Lstbl:	                                  ; box, where its payload and entry count go, header bytes, bytes per entry
	.ascii	"stts"
	.byte	TR_STTS, TR_NST, 8, 8
	.ascii	"ctts"
	.byte	TR_CTTS, TR_NCT, 8, 8
	.ascii	"stsc"
	.byte	TR_STSC, TR_NSC, 8, 12
	.ascii	"stsz"
	.byte	TR_STSZ, TR_N, 12, 0x84
	.ascii	"stco"
	.byte	TR_STCO, TR_NCH, 8, 4
	.ascii	"co64"
	.byte	TR_CO64, TR_NCH, 8, 8
	.ascii	"stss"
	.byte	TR_STSS, TR_NSS, 8, 4
	.long	0

; elst_shift(elst, end) — the track's start from its edit list: the first edit's media time, less a leading empty edit (x19 = track).
elst_shift:
	ldrb	w9, [x0]                  ; version: 32- or 64-bit fields
	ldr	w10, [x0, #4]
	rev	w10, w10                  ; edits
	add	x11, x0, #8
	mov	x12, #12
	cbz	w9, 1f
	mov	x12, #20
1:	mov	x15, #0                   ; empty edits, in movie units
Lel_edit:
	cbz	w10, Lel_none
	add	x13, x11, x12
	cmp	x13, x1
	b.hi	Lel_none
	cbnz	w9, 2f
	ldr	w13, [x11]
	rev	w13, w13
	ldr	w14, [x11, #4]
	rev	w14, w14
	sxtw	x14, w14
	b	3f
2:	ldr	x13, [x11]
	rev	x13, x13
	ldr	x14, [x11, #8]
	rev	x14, x14
3:	cmn	x14, #1
	b.ne	Lel_found
	add	x15, x15, x13             ; empty: the media starts later
	add	x11, x11, x12
	sub	w10, w10, #1
	b	Lel_edit
Lel_found:
	ldr	w9, [x19, #TR_TS]
	mul	x15, x15, x9
	ldr	w9, [x27, #E_MTS]
	udiv	x15, x15, x9
	sub	x14, x14, x15
	str	x14, [x19, #TR_SHIFT]
Lel_none:
	ret

; The cursor (x19 = track): sample I's size, duration, composition offset, sync flag and file offset, read from its tables as it steps.

; cur_size -> x0 = the sample's size.
cur_size:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, Lxc_size
	ldr	w0, [x19, #TR_FIXED]
	cbnz	w0, 1f
	ldr	x9, [x19, #TR_STSZ]
	ldr	w10, [x19, #TR_I]
	add	x9, x9, x10, lsl #2
	ldr	w0, [x9, #12]
	rev	w0, w0
1:	ret

; cur_delta -> x0 = the sample's duration.
cur_delta:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, Lxc_delta
	ldr	x9, [x19, #TR_STTS]
	ldr	w10, [x19, #TR_STI]
	add	x9, x9, x10, lsl #3
	ldr	w0, [x9, #12]
	rev	w0, w0
	ret

; cur_cts -> x0 = the sample's composition offset.
cur_cts:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, Lxc_cts
	mov	x0, #0
	ldr	w10, [x19, #TR_NCT]
	cbz	w10, 1f
	ldr	x9, [x19, #TR_CTTS]
	ldr	w10, [x19, #TR_CTI]
	add	x9, x9, x10, lsl #3
	ldr	w0, [x9, #12]
	rev	w0, w0
	sxtw	x0, w0
1:	ret

; cur_sync -> w0 = 1 for a sync sample (every one, without an stss).
cur_sync:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, Lxc_sync
	mov	w0, #1
	ldr	x9, [x19, #TR_STSS]
	cbz	x9, 1f
	ldr	w10, [x19, #TR_SSI]
	ldr	w11, [x19, #TR_NSS]
	mov	w0, #0
	cmp	w10, w11
	b.hs	1f
	add	x9, x9, x10, lsl #2
	ldr	w9, [x9, #8]
	rev	w9, w9
	ldr	w10, [x19, #TR_I]
	add	w10, w10, #1
	cmp	w9, w10
	cset	w0, eq
1:	ret
; Lxc_* — the same for a Matroska or FLV track: its cursor holds the frame's.
Lxc_size:
	ldr	w0, [x19, #TR_XSIZE]
	ret
Lxc_delta:
	ldr	w0, [x19, #TR_XDUR]
	ret
Lxc_cts:
	ldrsw	x0, [x19, #TR_XCTS]
	ret
Lxc_sync:
	ldr	w0, [x19, #TR_XSYNC]
	and	w0, w0, #1
	ret

; snap / unsnap — keep the cursor, or go back to the kept one.
snap:
	add	x9, x19, #TR_I
	add	x10, x19, #TR_SNAP
	b	Lsnap
unsnap:
	add	x9, x19, #TR_SNAP
	add	x10, x19, #TR_I
Lsnap:
	ld1	{ v0.16b, v1.16b, v2.16b, v3.16b }, [x9]
	st1	{ v0.16b, v1.16b, v2.16b, v3.16b }, [x10]
	ret

; cur_reset — to the first sample.
cur_reset:
	mov	w9, #-1
	stp	wzr, w9, [x19, #TR_I]     ; sample 0, before stts entry 0
	stp	wzr, w9, [x19, #TR_STL]   ; and ctts entry 0
	stp	wzr, wzr, [x19, #TR_CTL]
	stp	w9, wzr, [x19, #TR_CH]    ; chunk -1: cur_chunk takes it to 0
	str	wzr, [x19, #TR_SSI]
	str	xzr, [x19, #TR_DTS]
; cur_chunk — to the next chunk: its stsc entry, sample count and offset; then cur_norm.
cur_chunk:
	ldr	w9, [x19, #TR_CH]
	add	w9, w9, #1
	str	w9, [x19, #TR_CH]
	ldr	x10, [x19, #TR_STSC]
	ldr	w11, [x19, #TR_SCI]
	ldr	w13, [x19, #TR_NSC]
	add	w14, w9, #1               ; the chunk's number, from 1
Lcc_entry:
	add	w15, w11, #1
	cmp	w15, w13
	b.hs	Lcc_this
	mov	w16, #12
	umaddl	x16, w15, w16, x10
	ldr	w16, [x16, #8]
	rev	w16, w16                  ; the next entry's first chunk
	cmp	w16, w14
	b.hi	Lcc_this
	mov	w11, w15
	b	Lcc_entry
Lcc_this:
	str	w11, [x19, #TR_SCI]
	mov	w16, #12
	umaddl	x16, w11, w16, x10
	ldr	w16, [x16, #12]
	rev	w16, w16
	str	w16, [x19, #TR_CHL]
	mov	x10, #0x7fffffffffffffff  ; past the last chunk: nowhere
	ldr	w11, [x19, #TR_NCH]
	cmp	w9, w11
	b.hs	Lcc_off
	ldr	x10, [x19, #TR_CO64]
	cbz	x10, 1f
	add	x10, x10, x9, lsl #3
	ldr	x10, [x10, #8]
	rev	x10, x10
	b	Lcc_off
1:	ldr	x10, [x19, #TR_STCO]
	add	x10, x10, x9, lsl #2
	ldr	w10, [x10, #8]
	rev	w10, w10
Lcc_off:
	str	x10, [x19, #TR_OFF]
; cur_norm — past the stts and ctts runs a step used up, and stss up to the sample.
cur_norm:
	ldr	w9, [x19, #TR_STL]
	cbnz	w9, Lcn_ct
	ldr	w10, [x19, #TR_STI]
	add	w10, w10, #1
	ldr	w11, [x19, #TR_NST]
	cmp	w10, w11
	b.hs	Lcn_ct
	str	w10, [x19, #TR_STI]
	ldr	x11, [x19, #TR_STTS]
	add	x11, x11, x10, lsl #3
	ldr	w11, [x11, #8]
	rev	w11, w11
	str	w11, [x19, #TR_STL]
	b	cur_norm
Lcn_ct:
	ldr	w9, [x19, #TR_CTL]
	cbnz	w9, Lcn_ss
	ldr	w10, [x19, #TR_CTI]
	add	w10, w10, #1
	ldr	w11, [x19, #TR_NCT]
	cmp	w10, w11
	b.hs	Lcn_ss
	str	w10, [x19, #TR_CTI]
	ldr	x11, [x19, #TR_CTTS]
	add	x11, x11, x10, lsl #3
	ldr	w11, [x11, #8]
	rev	w11, w11
	str	w11, [x19, #TR_CTL]
	b	Lcn_ct
Lcn_ss:
	ldr	x9, [x19, #TR_STSS]
	cbz	x9, Lcn_done
	ldr	w10, [x19, #TR_SSI]
	ldr	w11, [x19, #TR_NSS]
	ldr	w12, [x19, #TR_I]
	add	w12, w12, #1
1:	cmp	w10, w11
	b.hs	2f
	add	x13, x9, x10, lsl #2
	ldr	w13, [x13, #8]
	rev	w13, w13
	cmp	w13, w12
	b.hs	2f
	add	w10, w10, #1
	b	1b
2:	str	w10, [x19, #TR_SSI]
Lcn_done:
	ret

; cur_step — on to the next sample.
cur_step:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, xs_step
	FRAME	0
	bl	cur_size
	mov	x12, x0
	bl	cur_delta
	ldr	x10, [x19, #TR_DTS]
	add	x10, x10, x0
	str	x10, [x19, #TR_DTS]
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	str	w9, [x19, #TR_I]
	ldr	w9, [x19, #TR_STL]
	sub	w9, w9, #1
	str	w9, [x19, #TR_STL]
	ldr	w9, [x19, #TR_CTL]
	sub	w9, w9, #1
	str	w9, [x19, #TR_CTL]
	ldr	w9, [x19, #TR_CHL]
	subs	w9, w9, #1
	str	w9, [x19, #TR_CHL]
	b.le	1f
	ldr	x10, [x19, #TR_OFF]
	add	x10, x10, x12
	str	x10, [x19, #TR_OFF]
	bl	cur_norm
	b	Lret0
1:	bl	cur_chunk
	b	Lret0

; cur_seek(target, run) — to the last sync sample at or before the one holding target (media units); run > 1 stops run - 1 samples earlier.
cur_seek:
	FRAME	2
	mov	x20, x0
	mov	w21, w1
	ldr	w9, [x19, #TR_CUR]
	cbz	w9, 1f
	bl	xs_start                  ; Matroska, FLV: from where their index puts the moment
	b	2f
1:	bl	cur_reset
2:	bl	snap
Lcs_step:
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lcs_done                  ; the last sample
	bl	cur_delta
	ldr	x9, [x19, #TR_DTS]
	madd	x9, x0, x21, x9
	cmp	x9, x20
	b.gt	Lcs_done
	bl	cur_step
	bl	cur_sync
	cbz	w0, Lcs_step
	bl	cur_cts                   ; a sync sample shown after the target is no start: its leading pictures need the one before
	ldr	x9, [x19, #TR_DTS]
	add	x9, x9, x0
	cmp	x9, x20
	b.gt	Lcs_step
	bl	snap
	b	Lcs_step
Lcs_done:
	bl	unsnap
	ldr	w9, [x19, #TR_KIND]       ; a picture from the file: the target becomes the time of the frame showing there, the latest at or before it (orders differ: no duration tells it)
	ldr	w10, [x19, #TR_SRC]
	cmp	w9, #'v'
	ccmp	w10, #0, #0, eq
	b.ne	Lret2
	bl	snap
	mov	x21, #0x8000000000000000  ; none yet
	mov	w22, #8                   ; frames looked at past the target's decode time: a B-pyramid's reach
1:	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	2f
	bl	cur_cts
	ldr	x9, [x19, #TR_DTS]
	add	x10, x9, x0
	cmp	x10, x20
	ccmp	x10, x21, #4, le
	csel	x21, x10, x21, gt
	cmp	x9, x20
	b.le	3f
	subs	w22, w22, #1
	b.eq	2f
3:	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	2f                        ; the last sample
	bl	cur_step
	b	1b
2:	bl	unsnap
	mov	x9, #0x8000000000000000
	cmp	x21, x9
	add	x10, x20, #1              ; none at or before it: the first after it shows
	csel	x21, x10, x21, eq
	ldr	x9, [x19, #TR_SHIFT]
	sub	x9, x21, x9
	str	x9, [x19, #TR_TGT]
	b	Lret2

; setflag(attachments, key) — attachments[*key] = kCFBooleanTrue.
setflag:
	ldr	x1, [x1]
	ldr	x2, [x27, #F_kCFBooleanTrue]
	ldr	x2, [x2]
	JUMPF	CFDictionarySetValue

; mk_sample(bb, offset, size, dts, pts, duration, sync) -> a ready CMSampleBuffer (retained) over bb's bytes, marked for the track's target; 0 if it could not be made (x19 = track).
; Lmk_samples: the same for w7 samples in a row, as long each, their sizes at x8 when more than one (x8 = 0: all as large).
	.equ MS_TIME,	16                ; CMSampleTimingInfo: duration, presentation and decode times
	.equ MS_LEN,	88
	.equ MS_BB,	96
	.equ MS_SB,	104
mk_sample:
	mov	w7, #1
Lmk_samples:
	FRAME	4, 112
	mov	w25, w7
	mov	x26, x8
	ldr	w9, [x19, #TR_KIND]       ; CC1 shown: a picture's SEI carries its captions
	ldr	x10, [x27, #E_SUBT]
	ldr	x11, [x27, #E_CCT]
	cmp	w9, #'v'
	ccmp	x10, x11, #0, eq
	ccmp	x10, #0, #4, eq
	b.eq	1f
	stp	x0, x1, [sp, #16]
	stp	x2, x3, [sp, #32]
	stp	x4, x5, [sp, #48]
	str	x6, [sp, #64]
	ldr	w9, [x19, #TR_TS]         ; its time on the captions' 90 kHz
	mov	x10, #(90000 & 0xffff)
	movk	x10, #(90000 >> 16), lsl #16
	mul	x3, x4, x10
	sdiv	x3, x3, x9
	bl	cc_avcc
	ldp	x0, x1, [sp, #16]
	ldp	x2, x3, [sp, #32]
	ldp	x4, x5, [sp, #48]
	ldr	x6, [sp, #64]
1:	sub	w9, w25, #1
	madd	x9, x9, x5, x4
	str	x9, [x19, #TR_LAST]
	mov	x20, x4
	mov	x21, x5
	mov	w22, w6
	mov	x23, x3
	str	x2, [sp, #MS_LEN]
	mov	x3, x2
	mov	x2, x1
	mov	x1, x0
	mov	x0, #0
	mov	w4, #0
	add	x5, sp, #MS_BB
	CALLF	CMBlockBufferCreateWithBufferReference
	cbnz	w0, Lnil4
	ldr	w24, [x19, #TR_TS]
	orr	x24, x24, #(1 << 32)      ; timescale, kCMTimeFlags_Valid
	stp	x21, x24, [sp, #MS_TIME]
	str	xzr, [sp, #(MS_TIME + 16)]
	stp	x20, x24, [sp, #(MS_TIME + 24)]
	str	xzr, [sp, #(MS_TIME + 40)]
	stp	x23, x24, [sp, #(MS_TIME + 48)]
	str	xzr, [sp, #(MS_TIME + 64)]
	add	x9, sp, #MS_SB
	str	x9, [sp]                  ; the 9th argument
	mov	x0, #0
	ldr	x1, [sp, #MS_BB]
	ldr	x2, [x19, #TR_FD]
	mov	x3, x25
	mov	x4, #1
	add	x5, sp, #MS_TIME
	mov	x6, x25
	add	x7, sp, #MS_LEN
	cmp	w25, #1
	b.eq	1f
	mov	x7, x26
	cbnz	x26, 1f
	mov	x6, #1                    ; no sizes: PCM, one size for every frame
	add	x7, sp, #MS_LEN
	ldr	x9, [x7]
	udiv	x9, x9, x25
	str	x9, [x7]
1:	CALLF	CMSampleBufferCreateReady
	mov	w23, w0
	ldr	x0, [sp, #MS_BB]
	bl	_CFRelease                ; the sample keeps it
	cbnz	w23, Lnil4
	ldr	x23, [sp, #MS_SB]
	mov	x0, x23
	mov	w1, #1
	CALLF	CMSampleBufferGetSampleAttachmentsArray
	mov	x1, #0
	CALLF	CFArrayGetValueAtIndex
	mov	x24, x0
	cbnz	w22, 1f
	ldr	x1, [x27, #F_kCMSampleAttachmentKey_NotSync]
	bl	setflag
1:	ldr	x9, [x19, #TR_TGT]
	subs	x9, x9, x20               ; how much of it is before the target
	b.le	Lms_shown
	ldr	w10, [x19, #TR_KIND]
	cmp	w10, #'v'
	b.ne	Lms_trim
	ldr	w10, [x19, #TR_SRC]       ; a picture: hidden before the target, for a file's the frame showing there (cur_seek); a stream's if it ends before it (or its length is unknown)
	cbz	w10, 4f
	cmp	x21, #0
	ccmp	x9, x21, #2, ne
	b.lo	Lms_shown                 ; the target falls in it: shown
4:	mov	x0, x23                   ; one no picture refers to is not even decoded
	bl	pic_ref
	cbnz	w0, 2f
	mov	x0, x23
	bl	_CFRelease
	b	Lnil4
2:	ldr	w9, [x27, #E_NET]         ; a stream's first picture after a seek is shown at once, while the rest comes
	ldr	w10, [x27, #E_PREV]
	cmp	w9, #0
	ccmp	w10, #0, #0, ne
	b.ne	3f
	mov	w9, #1
	str	w9, [x27, #E_PREV]
	b	Lms_ok
3:	mov	x0, x24                   ; decoded, never shown
	ldr	x1, [x27, #F_kCMSampleAttachmentKey_DoNotDisplay]
	bl	setflag
	b	Lms_ok
Lms_shown:
	ldr	w10, [x19, #TR_KIND]      ; the earliest picture shown: a seek's clock may have to move to it
	cmp	w10, #'v'
	b.ne	Lms_ok
	mov	x11, #1000
	mul	x11, x20, x11
	ldr	w10, [x19, #TR_TS]
	add	x11, x11, x10             ; rounded up (and so never 0): the clock at or past it
	sdiv	x11, x11, x10
	ldr	x10, [x27, #E_FIRSTMS]
	sub	x12, x10, #1
	cmp	x11, x12
	csel	x11, x11, x10, ls         ; the smaller, 0 counting as none
	str	x11, [x27, #E_FIRSTMS]
	b	Lms_ok
Lms_trim:
	mov	x0, x23                   ; sound before it: decoded, cut
	mov	x1, x9
	mul	x2, x21, x25
	bl	trim
Lms_ok:
	mov	x0, x23
	b	Lret4

; pic_ref(sample) -> w0 = 0 for an H.264 or HEVC picture no other refers to (nal_ref_idc 0, or a sub-layer non-reference type), else 1 (x19 = track).
pic_ref:
	FRAME	1, 16
	mov	x20, x0
	ldr	x0, [x19, #TR_FD]
	bl	_CMFormatDescriptionGetMediaSubType
	lsr	w9, w0, #8
	mov	w10, #0x7663
	movk	w10, #0x61, lsl #16       ; 'avc'
	cmp	w9, w10
	cset	w19, eq                   ; 1: H.264
	mov	w10, #0x6331
	movk	w10, #0x6876, lsl #16     ; 'hvc1'
	cmp	w0, w10
	mov	w10, #0x7631
	movk	w10, #0x6865, lsl #16     ; 'hev1'
	ccmp	w0, w10, #4, ne
	mov	w9, #2
	csel	w19, w9, w19, eq          ; 2: HEVC
	mov	w0, #1
	cbz	w19, Lpr_end
	mov	x0, x20
	bl	_CMSampleBufferGetDataBuffer
	stp	xzr, xzr, [sp]
	mov	x1, #0
	mov	x2, sp
	mov	x3, #0
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x9, x10, [sp]
	add	x9, x10, x9               ; the end
	mov	w0, #1
1:	add	x11, x10, #5              ; its first picture slice
	cmp	x11, x9
	b.hi	Lpr_end
	ldr	w11, [x10], #4
	rev	w11, w11
	ldrb	w12, [x10]
	add	x10, x10, x11
	cmp	w19, #1
	b.ne	2f
	and	w13, w12, #0x1f           ; H.264: slices are types 1-5
	sub	w13, w13, #1
	cmp	w13, #5
	b.hs	1b
	tst	w12, #0x60
	cset	w0, ne
	b	Lpr_end
2:	ubfx	w13, w12, #1, #6          ; HEVC: slices below 32; even ones below 16 are not referred to
	cmp	w13, #32
	b.hs	1b
	cmp	w13, #16
	and	w13, w13, #1
	ccmp	w13, #0, #0, lo
	cset	w0, ne
Lpr_end:
	ldr	x19, [x29, #-16]
	b	Lret1

; cur_sample(bb, base) -> the cursor's sample as a CMSampleBuffer over bb (holding the file from offset base), then the cursor moves on; 0 at the end (x19 = track).
; Sound from the mapped file takes in the samples right after it that last as long, up to 2^ABATCH.
cur_sample:
	ldr	w9, [x19, #TR_CUR]
	cbnz	w9, xs_sample
	FRAME	4, 8 << ABATCH
	mov	x25, x0
	mov	x26, x1
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lnil4
	bl	cur_delta
	mov	x21, x0
	bl	cur_cts
	mov	x22, x0
	bl	cur_sync
	mov	w23, w0
	ldr	x9, [x19, #TR_OFF]
	sub	x26, x9, x26              ; where it starts in bb
	mov	x20, #0                   ; the bytes, their sizes on the stack
	mov	x24, sp
	bl	cur_size
Lcs_add:
	str	x0, [x24], #8
	add	x20, x20, x0
	bl	cur_step
	ldr	w9, [x19, #TR_KIND]
	ldr	x10, [x27, #E_PARENT]
	cmp	w9, #'a'
	ccmp	x25, x10, #0, eq
	b.ne	Lcs_make
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lcs_make
	bl	cur_delta
	cmp	x0, x21
	b.ne	Lcs_make
	bl	cur_size
	ldr	x9, [x19, #TR_OFF]
	add	x10, x26, x20
	cmp	x9, x10                   ; right after
	add	x9, x9, x0
	ldr	x10, [x27, #E_LEN]
	ccmp	x9, x10, #2, eq           ; and in the file
	b.hi	Lcs_make
	add	x9, sp, #(8 << ABATCH)
	cmp	x24, x9
	b.lo	Lcs_add                   ; room
Lcs_make:
	mov	x8, sp
	sub	x7, x24, x8
	lsr	x7, x7, #3                ; how many
	mov	x0, x25
	mov	x1, x26
	mov	x2, x20
	ldr	x3, [x19, #TR_DTS]
	msub	x3, x7, x21, x3           ; the first one's decode time
	ldr	x9, [x19, #TR_SHIFT]
	sub	x3, x3, x9                ; after the edit
	add	x4, x3, x22
	mov	x5, x21
	mov	w6, w23
	bl	Lmk_samples
	b	Lret4
; produce() -> the track's next sample (retained): from the mapped file, or from its stream's queue; 0 when there is none now (x19 = track).
produce:
	FRAME	1
	ldr	w9, [x19, #TR_SRC]
	cbnz	w9, Lpd_pop
Lpd_file:
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.lo	2f
	ldr	w9, [x19, #TR_MWAIT]
	cbz	w9, Lpd_none
	bl	xs_step
	cbz	w0, Lpd_none
2:	ldr	w9, [x19, #TR_KIND]       ; a playing picture at most LEAD_MS ahead of the clock: a seek's flush costs ~1 ms per queued sample
	ldr	w10, [x27, #E_SLOW]
	cmp	w9, #'v'
	ccmp	w10, #0, #0, eq
	b.ne	1f
	bl	now_ms
	add	x0, x0, #LEAD_MS
	ldr	w9, [x19, #TR_TS]
	mul	x0, x0, x9
	mov	x9, #1000
	udiv	x0, x0, x9
	ldr	x9, [x19, #TR_DTS]
	cmp	x9, x0
	b.gt	Lpd_none                  ; net_tick asks again
1:
	bl	cur_size
	ldr	x9, [x19, #TR_OFF]
	add	x9, x9, x0
	ldr	x10, [x27, #E_LEN]
	cmp	x9, x10
	b.hi	Lpd_none                  ; outside the file
	ldr	x0, [x27, #E_PARENT]
	mov	x1, #0
	bl	cur_sample
	cbz	x0, Lpd_file              ; not decoded (before a seek's target): the next one
	b	Lret1
Lpd_pop:
	ldp	w9, w10, [x19, #TR_FH]
	cmp	w9, w10
	b.eq	Lpd_empty
	ldr	x11, [x19, #TR_FQ]
	and	w12, w9, #(FIFO_N - 1)
	ldr	x20, [x11, x12, lsl #3]
	add	w9, w9, #1
	str	w9, [x19, #TR_FH]
	ldr	x0, [x19, #TR_ST]
	bl	st_pump                   ; room again: maybe fetch on
	mov	x0, x20
	b	Lret1
Lpd_empty:
	ldr	x9, [x19, #TR_ST]
	ldr	x10, [x19, #TR_AFS]
	cmp	x9, #0
	ccmp	x10, #0, #4, eq
	b.eq	1f
	bl	afs_more                  ; a sound file: more of it read
	cbnz	w0, Lpd_pop
1:	mov	w9, #1
	str	w9, [x19, #TR_STARVE]     ; the next sample asks the renderer again
	ldr	x0, [x19, #TR_ST]
	bl	st_pump
	ldp	w9, w10, [x19, #TR_FH]
	cmp	w9, w10
	b.ne	Lpd_pop
Lpd_none:
	mov	x0, #0
	b	Lret1

; q_push(sample) — onto the track's queue; a renderer that ran dry asks again (x19 = track).
q_push:
	ldp	w9, w10, [x19, #TR_FH]
	sub	w11, w10, w9
	cmp	w11, #FIFO_N
	b.hs	_CFRelease                ; full: dropped (the fetching stops long before)
	ldr	x12, [x19, #TR_FQ]
	and	w13, w10, #(FIFO_N - 1)
	str	x0, [x12, x13, lsl #3]
	add	w10, w10, #1
	str	w10, [x19, #TR_FT]
	ldr	w9, [x19, #TR_STARVE]
	cbz	w9, 1f
	str	wzr, [x19, #TR_STARVE]
	b	trk_request
1:	ret

; q_clear — drop the track's queued samples and fragment list (x19 = track).
q_clear:
	FRAME	1
Lqc_next:
	ldp	w9, w10, [x19, #TR_FH]
	cmp	w9, w10
	b.eq	Lqc_done
	ldr	x11, [x19, #TR_FQ]
	and	w12, w9, #(FIFO_N - 1)
	ldr	x0, [x11, x12, lsl #3]
	add	w9, w9, #1
	str	w9, [x19, #TR_FH]
	bl	_CFRelease
	b	Lqc_next
Lqc_done:
	stp	wzr, wzr, [x19, #TR_FN]   ; TR_FN, TR_FI
	mov	w9, #1
	str	w9, [x19, #TR_STARVE]
	b	Lret1

; trk_request — the track's renderer asks for samples again, if it is a playing track (x19 = track).
trk_request:
	ldr	x9, [x27, #E_VT]
	cmp	x9, x19
	b.ne	1f
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, 3f                    ; Audio Only decodes no picture
	ldr	x0, [x27, #E_VR]
	ADDR	x3, Lblk_v
	b	2f
1:	ldr	x9, [x27, #E_AT]
	cmp	x9, x19
	b.ne	3f
	ldr	x0, [x27, #E_AR]
	ADDR	x3, Lblk_a
2:	ldr	x2, [x28, #G_MEDIAQ]
	ldr	x1, [x27, #S_requestMediaDataWhenReadyOnQueue_usingBlock_]
	b	_objc_msgSend
3:	ret

; feed_v / feed_a — a renderer wants more of its track.
	ENTRY	feed_v
	ldr	x0, [x27, #E_VT]
	ldr	x1, [x27, #E_VR]
	b	feed
	ENTRY	feed_a
	ldr	x0, [x27, #E_AT]
	ldr	x1, [x27, #E_AR]
; feed(track, renderer) — enqueue samples while the renderer takes them; at the end it stops asking.
feed:
	FRAME	2, 0, 1
	cbz	x19, Lfe_stop
Lfe_more:
	mov	x0, x20
	SEND	S_isReadyForMoreMediaData
	cbz	w0, Lret2
	bl	produce
	cbz	x0, Lfe_stop
	mov	x21, x0
	mov	x2, x0
	mov	x0, x20
	SEND	S_enqueueSampleBuffer_
	mov	x0, x21
	bl	_CFRelease
	b	Lfe_more
Lfe_stop:
	mov	x0, x20
	SEND	S_stopRequestingMediaData
	b	Lret2

; trk_play(track, renderer, block, ms) — the renderer drops what it holds, and the track plays from that moment, decoded from the sync sample before it.
trk_play:
	FRAME	2, 0, 1
	mov	x21, x2
	mov	x22, x3
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'a'
	b.ne	1f
	mov	x0, x19
	bl	snd_fd
	cbz	x0, Lret2                 ; a sound CoreMedia cannot read does not play
1:	mov	x0, x20
	SEND	S_stopRequestingMediaData
	mov	x0, x20
	SEND	S_flush
	mov	x1, x22
	bl	trk_tgt
	ldr	x9, [x19, #TR_AFS]
	cbz	x9, 1f
	mov	x0, x22                   ; a sound file
	bl	afs_seek
	b	2f
1:	bl	trk_seek
2:	mov	x0, x20
	ldr	x2, [x28, #G_MEDIAQ]
	mov	x3, x21
	SEND	S_requestMediaDataWhenReadyOnQueue_usingBlock_
	b	Lret2

; eng_seek(ms) — show that moment exactly: the clock holds there until its picture is ready, then goes on as before.
	VMENTRY	eng_seek, Lp_seek
	.pushsection __DATA,__data
Lp_seek:
	GL	0
	STE	E_TGTMS
	IMM	0
	STE	E_FIRSTMS
	STEW	E_PREV
	STE	E_T0
	LDEW	E_NET
	JNZ	Lp_seek_net
	LDE	E_VT
	SL	1
	LDE	E_AT
	SL	2
	ADDL	1
	JZ	Lp_seek_end               ; nothing open
	GL	1
	JZ	Lp_seek_sound
	LW	G_AONLY
	JNZ	Lp_seek_sound             ; Audio Only: no picture is decoded
	NCALL	hold_async, "a"
	NCALL	trk_play, "bEPa"
	.short	E_VR
	.long	Lblk_v - Lvm_base
	GL	2
	JZ	Lp_seek_wait
	LDE	E_AR                      ; the old sound stops now, the new comes after the first pictures
	MSG	S_stopRequestingMediaData
	CALL	F_dispatch_async_f, "OaP"
	.byte	G_MEDIAQ >> 3
	.long	seek_sound - Lvm_base
	JMP	Lp_seek_wait
	HERE	Lp_seek_sound             ; no picture: the clock and the sound at once
	NCALL	hold, "a"
	GL	2
	JZ	Lp_seek_wait
	NCALL	trk_play, "cEPa"
	.short	E_AR
	.long	Lblk_a - Lvm_base
	HERE	Lp_seek_wait
	NCALL	sub_seek, "a"
	NCALL	await
	HERE	Lp_seek_end
	OP_END
	HERE	Lp_seek_net
	NCALL	hold_async, "a"
	LDE	E_VR                      ; streams: both renderers drop what they hold, each stream seeks
	MSG	S_stopRequestingMediaData
	LDE	E_VR
	MSG	S_flush
	LDE	E_AR
	MSG	S_stopRequestingMediaData
	LW	G_AONLY
	JZ	Lp_seek_pic
	LDE	E_ST + ST_SIZE + ST_URL
	SL	2
	LDE	E_ST + ST_SIZE + ST_PLURL
	ADDL	2
	JNZ	Lp_seek_streams           ; Audio Only: the picture's stream stays still
	HERE	Lp_seek_pic
	NCALL	st_seek, "Ba"
	.short	E_ST
	HERE	Lp_seek_streams
	NCALL	st_seek, "Ba"
	.short	E_ST + ST_SIZE
	NCALL	st_seek, "Ba"
	.short	E_ST + 2 * ST_SIZE
	LDE	E_AR                      ; the sound's flush once the requests are out
	MSG	S_flush
	JMP	Lp_seek_wait
	.popsection

; hold(ms) — the clock stops at that moment until await lets it go.
hold:
	mov	w9, #1
	str	w9, [x27, #E_HOLD]
Lhold_rate:
	FRAME	0, 32
	mov	x9, #1000
	orr	x9, x9, #(1 << 32)
	stp	x0, x9, [sp]              ; CMTime in milliseconds
	str	xzr, [sp, #16]
	ldr	x0, [x27, #E_SYNC]
	movi	d0, #0
	mov	x2, sp
	SEND	S_setRate_time_
	b	Lret0

; hold_async(ms) — hold, with the stop itself on the clock queue: stopping a playing clock waits ~35 ms for the sound device, so the media queue waits only until the clock shows the moment.
hold_async:
	VM	Lp_holda
	.pushsection __DATA,__data
Lp_holda:
	IMM	1
	STEW	E_HOLD
	LDEW	E_HOLDGEN
	ADDI	1
	STEW	E_HOLDGEN
	SL	2                         ; c: this hold
	SHL	48
	ADDL	0
	SL	3                         ; d: it with the moment
	CALL	F_dispatch_async_f, "OdP"
	.byte	G_CLOCKQ >> 3
	.long	hold_job - Lvm_base
	IMM	0
	SL	1                         ; b: tries, ~30 ms of them at most
	HERE	Lp_holda_wait
	NCALL	now_ms, "="
	EQL	0
	JZ	Lp_holda_next             ; not at the moment yet
	LDEW	E_HOLDGO
	EQL	2
	JNZ	Lp_holda_end              ; and this hold started: the clock shows it
	HERE	Lp_holda_next
	GL	1
	ADDI	1
	SL	1
	BIT	15
	JZ	Lp_holda_wait
	HERE	Lp_holda_end
	OP_END
	.popsection

; hold_job(hold << 48 | ms) — the clock queue's part of hold_async.
	ENTRY	hold_job
	FRAME	1, 0, 1
	lsr	x9, x19, #48
	str	w9, [x27, #E_HOLDGO]
	and	x0, x19, #0xffffffffffff
	bl	Lhold_rate
	lsr	x9, x19, #48
	str	w9, [x27, #E_HOLDDONE]
	b	Lret1

; seek_sound(ms) — the sound track from that moment: after a seek's first pictures, as its renderer's flush takes ~11 ms.
	VMENTRY	seek_sound, Lp_ssound
	.pushsection __DATA,__data
Lp_ssound:
	LDE	E_AT
	SL	1
	JZ	Lp_ssound_end
	NCALL	trk_play, "bEPa"
	.short	E_AR
	.long	Lblk_a - Lvm_base
	HERE	Lp_ssound_end
	OP_END
	.popsection

snd_watch:
	FRAME	0
	CALLF	CFNotificationCenterGetLocalCenter
	mov	x1, #0
	adr	x2, snd_flushed
	mov	x3, #0
	ldr	x4, [x27, #E_AR]
	mov	x5, #4
	CALLF	CFNotificationCenterAddObserver
	b	Lret0

	ENTRY	snd_flushed
	adr	x0, snd_again
	b	eng_cmd

	ENTRY	snd_again
	FRAME	0
	ldr	x9, [x27, #E_AT]
	cbz	x9, Lret0
	bl	now_ms
	ldr	w9, [x27, #E_NET]
	cbz	w9, 1f
	ldr	w9, [x27, #E_LIVE]
	cbnz	w9, Lret0
	ldr	x9, [x27, #E_DURMS]
	cbz	x9, Lret0
	bl	eng_seek
	b	Lret0
1:	bl	seek_sound
	b	Lret0

; await — wait for the first picture, then the clock may run.
await:
	mov	w9, #WAIT_TRIES
	str	w9, [x27, #E_WAITN]
	ldr	w0, [x27, #E_WAITGEN]
	add	w0, w0, #1
	str	w0, [x27, #E_WAITGEN]
	b	Leng_wait

; eng_seekq — the newest seek the main thread queued.
	ENTRY	eng_seekq
	add	x9, x28, #G_SEEKPEND
	swpal	wzr, w10, [x9]
	ldr	x0, [x28, #G_SEEKTO]
	b	eng_seek

; eng_wait(generation) — every 5 ms until the picture at the seek is ready (or a second passed): then the clock may run.
	ENTRY	eng_wait
	FRAME	0
	ldr	w9, [x27, #E_WAITGEN]
	cmp	w0, w9
	b.ne	Lret0                     ; a newer seek waits instead
	ldr	w9, [x27, #E_WANTV]
	cbz	w9, Lew_go
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, Lew_go
	ldr	w9, [x27, #E_WAITN]
	subs	w9, w9, #1
	b.lo	Lew_go
	str	w9, [x27, #E_WAITN]
	ldr	x0, [x28, #G_SBLAYER]
	SEND	S_isReadyForDisplay
	ldr	x10, [x27, #E_FIRSTMS]
	cmp	w0, #0
	ccmp	x10, #0, #4, ne
	b.eq	2f                        ; not ready with the seek's own picture (a stream's first, shown early, does not count)
	tbnz	x10, #63, Lew_go          ; ready on the poll before too: the first picture ready may be a B-picture's reference, after the target
	orr	x10, x10, #(1 << 63)
	str	x10, [x27, #E_FIRSTMS]
2:
	ldr	w9, [x27, #E_WAITN]
	cmp	w9, #(WAIT_TRIES - 40)
	b.hi	1f                        ; a moment for every picture of the first segment to come
	mov	x0, x10                   ; the earliest picture comes after the target (HLS segments): the clock holds at it
	ldr	x9, [x27, #E_TGTMS]
	cmp	x0, x9
	b.le	1f
	str	x0, [x27, #E_TGTMS]
	bl	hold
1:
	mov	x0, #0                    ; DISPATCH_TIME_NOW
	mov	w1, #(WAIT_NS & 0xffff)
	movk	w1, #(WAIT_NS >> 16), lsl #16
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	ldr	w2, [x27, #E_WAITGEN]
	adr	x3, eng_wait
	bl	_dispatch_after_f
	b	Lret0
Lew_go:
	str	wzr, [x27, #E_HOLD]
	ldr	w9, [x27, #E_HOLDGEN]
	ldr	w10, [x27, #E_HOLDDONE]
	cmp	w9, w10
	b.eq	1f
	ldr	x0, [x28, #G_CLOCKQ]      ; the clock goes on after its hold, on the queue that holds it
	mov	x1, #0
	adr	x2, eng_rate
	bl	_dispatch_async_f
	b	Lret0
1:	bl	Leng_rate
	b	Lret0

; eng_rate — the clock runs at the chosen speed while playing, else holds; not while a seek waits for its picture.
	ENTRY	eng_rate
	ldr	w9, [x27, #E_HOLD]
	cbnz	w9, 1f
	ldr	x0, [x27, #E_SYNC]
	ldr	s0, [x28, #G_RATE]
	movi	d1, #0
	ldr	w9, [x28, #G_PLAYING]
	cmp	w9, #0
	fcsel	s0, s0, s1, ne
	SENDT	S_setRate_
1:	ret

; now_ms -> x0 = the clock, ms.
now_ms:
	FRAME	0, 32
	stp	xzr, xzr, [sp]            ; 0 before the synchronizer exists
	ldr	x0, [x27, #E_SYNC]
	mov	x8, sp
	SEND	S_currentTime
	ldr	x9, [sp]
	ldrsw	x10, [sp, #8]
	mov	x11, #1000
	mul	x9, x9, x11
	sdiv	x0, x9, x10
	b	Lret0

; sub_tick(block, time) — the clock moved: the subtitle track's cues up to now are shown in turn, the last one until it ends.
	ENTRY	sub_tick
	FRAME	2, 32
	ldr	x19, [x27, #E_SUBT]
	cbz	x19, Lret2
	ldr	x9, [x1]                  ; now, in the track's units
	ldr	w10, [x1, #8]
	ldr	w11, [x19, #TR_TS]
	mul	x9, x9, x11
	sdiv	x20, x9, x10
Lsb_next:
	ldr	x0, [x27, #E_SUBN]
	cbnz	x0, 1f
	bl	produce
	cbz	x0, Lsb_end
	str	x0, [x27, #E_SUBN]
1:	mov	x8, sp
	CALLF	CMSampleBufferGetPresentationTimeStamp
	ldr	x21, [sp]
	cmp	x21, x20
	b.gt	Lsb_end                   ; not yet
	ldr	x0, [x27, #E_SUBN]
	mov	x8, sp
	CALLF	CMSampleBufferGetDuration
	ldr	x9, [sp]
	add	x9, x21, x9
	str	x9, [x27, #E_SUBEND]
	ldr	x0, [x27, #E_SUBN]
	str	xzr, [x27, #E_SUBN]
	bl	sub_cue
	b	Lsb_next
Lsb_end:
	ldr	w9, [x27, #E_SUBON]
	cbz	w9, Lret2
	ldr	x10, [x27, #E_SUBEND]
	cmp	x20, x10
	b.lt	Lret2
	mov	x0, #0                    ; it ended
	bl	sub_text
	b	Lret2

; sub_cue(sample) — the cue's text, from its format: tx3g or QuickTime text (a length, then UTF-8), or WebVTT boxes; the sample is released.
sub_cue:
	FRAME	3, 32, 1
	CALLF	CMSampleBufferGetFormatDescription
	bl	_CMFormatDescriptionGetMediaSubType
	mov	w20, w0
	mov	x0, x19
	bl	_CMSampleBufferGetDataBuffer
	stp	xzr, xzr, [sp]
	mov	x1, #0
	mov	x2, #0
	mov	x3, sp
	add	x4, sp, #8
	bl	_CMBlockBufferGetDataPointer
	ldp	x22, x21, [sp]            ; length, bytes (0 without data)
	add	x22, x21, x22             ; the end
	TYPE	w9, 't','t','v','w'      ; 'wvtt'
	cmp	w20, w9
	b.eq	Lsu_vtt
	TYPE	w9, '8','0','6','c'      ; 'c608': field 1's byte pairs for the decoder, which keeps the caption shown
	cmp	w20, w9
	b.eq	Lsu_608
	mov	x0, x21                   ; 'mktx': Matroska's text, all of it
	mov	x1, x22
	TYPE	w9, 'x','t','k','m'
	cmp	w20, w9
	TYPE	w9, 'x','t','v','w'
	ccmp	w20, w9, #4, ne
	b.eq	Lsu_show
	TYPE	w9, 's','a','k','m'      ; 'mkas': an ASS event, its text after eight fields
	cmp	w20, w9
	mov	w9, #8
	mov	w11, #','
	b.eq	2f
	TYPE	w9, 'b','t','v','w'
	cmp	w20, w9
	b.ne	1f
	mov	w9, #2
	mov	w11, #'\n'
2:	cmp	x0, x22
	b.hs	Lsu_show
	ldrb	w10, [x0], #1
	cmp	w10, w11
	b.ne	2b
	subs	w9, w9, #1
	b.ne	2b
	b	Lsu_show
1:	add	x0, x21, #2               ; a length, then the text
	cmp	x0, x22
	b.hi	Lsu_none
	ldrh	w9, [x21]
	rev16	w9, w9
	add	x1, x0, x9
	cmp	x1, x22
	csel	x1, x1, x22, ls
	b	Lsu_show
Lsu_vtt:
	mov	x0, x21                   ; the cue box's payload box
	mov	x1, x22
	TYPE	w2, 'v','t','t','c'
	bl	box_find
	cbz	x0, Lsu_none              ; vtte: no cue
	TYPE	w2, 'p','a','y','l'
	bl	box_find
	cbnz	x0, Lsu_show
Lsu_none:
	mov	x0, #0
	mov	x1, #0
Lsu_show:
	sub	x1, x1, x0
Lsu_text:
	lsr	w2, w20, #16              ; Matroska's text ('mk..'): ASS's overrides and breaks too
	MOVL	w9, 0x6D6B
	cmp	w2, w9
	cset	w2, eq
	bl	sub_textn
Lsu_done:
	mov	x0, x19
	bl	_CFRelease
	b	Lret3
Lsu_608:
	mov	x0, x21
	mov	x1, x22
	TYPE	w2, 'c','d','a','t'
	bl	box_find
	cbz	x0, Lsu_done
	mov	x21, x0
	mov	x22, x1
	mov	x23, x19
	BADDR	x19, E_CC
1:	add	x9, x21, #2
	cmp	x9, x22
	b.hi	2f
	ldrb	w0, [x21], #1
	ldrb	w1, [x21], #1
	bl	cc_pair
	b	1b
2:	add	x0, x19, #(CC_D + 4)
	ldr	w1, [x19, #CC_D]
	mov	x19, x23
	b	Lsu_text

; sub_textn(bytes, length, matroska) — show that cue text: tags dropped (and Matroska's ASS overrides, its breaks kept), &amp; &lt; &gt; decoded; nothing clears it.
sub_textn:
	FRAME	2, 0, 1
	mov	w22, #'<'                 ; what starts a tag, and for Matroska's text an {override}
	mov	w9, #'{'
	cmp	w2, #0
	csel	w22, w9, w22, ne
	mov	x0, #0
	cbz	x20, 1f
	add	x0, x20, #1
	bl	_malloc
	cbz	x0, Lret2
	mov	x21, x0
	mov	x9, x19
	add	x10, x19, x20
	mov	x11, x0
	mov	w12, #0                   ; inside a tag
Ltn_ch:
	cmp	x9, x10
	b.hs	Ltn_end
	ldrb	w13, [x9], #1
	cmp	w13, #'<'
	ccmp	w13, w22, #4, ne
	csinc	w12, w12, wzr, ne
	cbnz	w12, Ltn_tag
	mov	w14, #'{'                 ; Matroska's: ASS's escapes
	cmp	w13, #'\\'
	ccmp	w22, w14, #0, eq
	b.eq	Ltn_esc
	cmp	w13, #'&'
	b.ne	Ltn_put
	sub	x14, x10, x9
	cmp	x14, #3
	b.lo	Ltn_put
	ldrh	w14, [x9]
	ldrb	w15, [x9, #2]
	TYPE	w16, 'l','t',0,0
	mov	w17, #'<'
	cmp	w14, w16
	b.eq	Ltn_ent
	TYPE	w16, 'g','t',0,0
	mov	w17, #'>'
	cmp	w14, w16
	b.eq	Ltn_ent
	TYPE	w16, 'a','m',0,0
	cmp	w14, w16
	b.ne	Ltn_put
	cmp	w15, #'p'
	b.ne	Ltn_put
	sub	x14, x10, x9
	cmp	x14, #4
	b.lo	Ltn_put
	ldrb	w15, [x9, #3]             ; &amp;
	cmp	w15, #';'
	b.ne	Ltn_put
	add	x9, x9, #4
	b	Ltn_put
Ltn_ent:
	cmp	w15, #';'                 ; &lt; &gt;
	b.ne	Ltn_put
	add	x9, x9, #3
	mov	w13, w17
Ltn_put:
	strb	w13, [x11], #1
	b	Ltn_ch
Ltn_tag:
	add	w14, w22, #2              ; '>', or '}'
	cmp	w13, #'>'
	ccmp	w13, w14, #4, ne
	csel	w12, wzr, w12, eq
	b	Ltn_ch
Ltn_esc:
	cmp	x9, x10                   ; ASS: \N and \n break the line, \h is a space
	b.hs	Ltn_put
	ldrb	w14, [x9]
	mov	w15, #10
	mov	w16, #'n'
	cmp	w14, #'N'
	ccmp	w14, w16, #4, ne
	b.eq	Ltn_brk
	mov	w15, #' '
	cmp	w14, #'h'
	b.ne	Ltn_put
Ltn_brk:
	add	x9, x9, #1
	mov	w13, w15
	b	Ltn_put
Ltn_end:
	strb	wzr, [x11]
	mov	x0, x21
	bl	mkstr
	SEND	S_retain                  ; main has it next
	mov	x20, x0
	mov	x0, x21
	bl	_free
	mov	x0, x20
1:	bl	sub_text
	b	Lret2

; sub_text(text) — main shows that NSString (released there), or clears with 0.
sub_text:
	cmp	x0, #0
	cset	w9, ne
	str	w9, [x27, #E_SUBON]
	mov	x1, x0
	adr	x0, sub_show
	b	post_main

; sub_reset — no cue shown or waiting, no caption decoded: another moment or track.
sub_reset:
	FRAME	0
	BADDR	x0, E_CC
	mov	x1, #CC_SIZE
	bl	_bzero
	ldr	x0, [x27, #E_SUBN]
	str	xzr, [x27, #E_SUBN]
	cbz	x0, 1f
	bl	_CFRelease
1:	str	xzr, [x27, #E_SUBEND]
	ldr	w9, [x27, #E_SUBON]
	cbz	w9, Lret0
	mov	x0, #0
	bl	sub_text
	b	Lret0

; sub_seek(ms) — the subtitles start again at that moment; a stream's track starts with its stream.
sub_seek:
	FRAME	1
	mov	x20, x0
	bl	sub_reset
	bl	sub_obs
	ldr	x19, [x27, #E_CCT]        ; the captions' cues come again with the picture
	cbz	x19, 1f
	bl	q_clear
1:	ldr	x0, [x27, #E_SUBT]
	cbz	x0, Lret1
	ldr	w9, [x0, #TR_SRC]
	cbnz	w9, Lret1
	mov	x1, #0                    ; no renderer
	mov	x2, #0
	mov	x3, x20
	bl	trk_play
	b	Lret1

; sub_obs — the subtitles follow the clock every 1/30 s, and on every jump, only while a track is shown: the observer costs about 1% of a core.
sub_obs:
	VM	Lp_subobs
	.pushsection __DATA,__data
Lp_subobs:
	LDE	E_SUBOBS
	SL	0                         ; a: the observer, if any
	LDE	E_SUBT
	JZ	Lp_subobs_off
	GL	0
	JNZ	Lp_subobs_end
	LDE	E_SYNC
	MSG	S_addPeriodicTimeObserverForInterval_queue_usingBlock_, "=MOP"
	.byte	24
	.quad	1
	.long	30, 1
	.quad	0
	.byte	G_MEDIAQ >> 3
	.long	Lblk_s - Lvm_base
	MSG	S_retain, "="
	STE	E_SUBOBS
	OP_END
	HERE	Lp_subobs_off
	GL	0
	JZ	Lp_subobs_end
	LDE	E_SYNC
	MSG	S_removeTimeObserver_, "a"
	GL	0
	MSG	S_release
	IMM	0
	STE	E_SUBOBS
	HERE	Lp_subobs_end
	OP_END
	.popsection

; sub_show(text) — the subtitle layer over the picture shows the text (released), centered near the bottom; 0 clears it.
	VMTENTRY	sub_show
	LDE	B_SUBL
	JNZ	Lp_subshow_made
	CLS	CATextLayer
	MSG	S_new, "="
	STE	B_SUBL
	MSG	S_setAlignmentMode_, "S"
	.asciz	"center"
	LD	G_WIN
	MSG	S_backingScaleFactor, "^"
	LDE	B_SUBL
	MSG	S_setContentsScale_, "Z"  ; sharp on Retina
	.byte	4
	FK	16
	FS	4
	LDE	B_SUBL
	MSG	S_setShadowOpacity_, "W"
	.byte	4
	CLS	NSFont
	MSG	S_systemFontOfSize_weight_, "=DF"
	.short	0
	.byte	X_SEMIBOLD
	SL	1
	LDE	B_SUBL
	MSG	S_setFont_, "b"
	LD	G_SBV                     ; beside the picture, not turned with it
	MSG	S_layer, "="
	MSG	S_addSublayer_, "E"
	.short	B_SUBL
	HERE	Lp_subshow_made
	CLS	CATransaction             ; at once, not faded in
	MSG	S_begin
	CLS	CATransaction
	MSG	S_setDisableActions_, "I"
	.byte	1
	LD	G_SBV
	MSG	S_bounds, "^"             ; g, h: the view's width and height
	FL	7
	FOPK	2, 2
	FOPK	2, 6                      ; the text: about 1/20 of the picture's height
	FS	3
	LDE	B_SUBL
	MSG	S_setFontSize_, "Z"
	.byte	3
	LDE	B_SUBL
	MSG	S_setWrapped_, "I"        ; measured on its own lines (wrapped, it measures stale)
	.byte	0
	LDE	B_SUBL
	MSG	S_setString_, "a"
	FL	6
	FS	1
	FOPK	2, 14                     ; the widest it goes
	FS	2
	LDE	B_SUBL
	MSG	S_preferredFrameSize, "^" ; e, f: its size
	FL	4
	FOP	6, 2
	JZ	Lp_subshow_fits
	FL	4                         ; wider: wrapped into more lines
	FOP	3, 2
	FOPK	7, 0
	FOP	2, 5
	FS	5
	FL	2
	FS	4
	LDE	B_SUBL
	MSG	S_setWrapped_, "I"
	.byte	1
	HERE	Lp_subshow_fits
	FL	1
	FOP	1, 4
	FOPK	2, 8                      ; centered, a line above the bottom edge
	FS	6
	LDE	B_SUBL
	MSG	S_setFrame_, "ZZZZ"
	.byte	6, 3, 4, 5
	CLS	CATransaction
	MSG	S_commit
	GL	0
	MSG	S_release
	OP_END
	.p2align 2

; eng_vol — the sound renderer takes G's volume and mute.
	ENTRY	eng_vol
	ldr	x0, [x27, #E_AR]
	b	vol_to

; eng_aonly — Audio Only: the picture stops being decoded, or comes back a moment ahead, decoded from its sync sample.
	VMENTRY	eng_aonly, Lp_eaonly
	.pushsection __DATA,__data
Lp_eaonly:
	LDEW	E_NET
	JNZ	Lp_eaonly_vod
	LDE	E_VT
	JZ	Lp_eaonly_end
	LW	G_AONLY
	JZ	Lp_eaonly_back
	LDE	E_VR
	MSG	S_stopRequestingMediaData
	LDE	E_VR
	MSG	S_flushWithRemovalOfDisplayedImage_completionHandler_, "II"
	.byte	1, 0
	OP_END
	HERE	Lp_eaonly_back
	NCALL	now_ms, "="
	ADDH	300                       ; 0.3 s ahead, while it decodes
	SL	0
	LDE	E_VT
	NCALL	trk_play, "VEPa"
	.short	E_VR
	.long	Lblk_v - Lvm_base
	HERE	Lp_eaonly_end
	OP_END
	HERE	Lp_eaonly_vod
	LDE	E_VR                      ; streams: the picture's stream stops, or starts again just ahead
	MSG	S_stopRequestingMediaData
	LDE	E_VR
	MSG	S_flushWithRemovalOfDisplayedImage_completionHandler_, "II"
	.byte	1, 0
	LDE	E_ST + ST_SIZE + ST_URL
	SL	2
	LDE	E_ST + ST_SIZE + ST_PLURL
	ADDL	2
	SL	2                         ; c: a sound stream of its own
	LW	G_AONLY
	JZ	Lp_eaonly_off
	LDE	E_VT                      ; on: what is queued goes; YouTube's picture stream stops (one stream for both goes on, its pictures dropped)
	JZ	Lp_eaonly_kept
	NCALL	trk_target, "VX"
	.long	0xffffffff
	HERE	Lp_eaonly_kept
	GL	2
	JZ	Lp_eaonly_done
	NCALL	st_reset, "B"
	.short	E_ST
	IMM	1
	STEW	E_ST + ST_EOS
	OP_END
	HERE	Lp_eaonly_off
	NCALL	now_ms, "="
	SL	3
	GL	2
	JZ	Lp_eaonly_all             ; off, one stream for both: everything restarts from now
	IMM	0                         ; its first picture shown at once, like a seek's
	STEW	E_PREV
	GL	3
	ADDH	1000                      ; YouTube: its picture stream from a second ahead, fetched and decoded meanwhile
	SL	3
	LDEW	E_LIVE
	MULH	1000
	ADDL	3
	STE	E_TGTMS
	NCALL	st_seek, "BV"
	.short	E_ST
	OP_END
	HERE	Lp_eaonly_all
	NCALL	eng_seek, "d"
	HERE	Lp_eaonly_done
	OP_END
	.popsection

; net_tick(generation) — every eighth of a second: a stream's track running dry holds the clock until STALL_FULL ms are in again; a picture held back by its lead is asked for again.
	ENTRY	net_tick
	FRAME	2, 32
	mov	w19, w0
	ldr	w9, [x27, #E_GEN]
	cmp	w0, w9
	b.ne	Lret2                     ; other media now: no more ticks
	bl	now_ms
	mov	x20, x0                   ; the clock, ms
	ldr	x0, [x27, #E_SUBT]
	bl	nt_feed
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	orr	x9, x9, x10
	cmp	x9, #0
	csetm	x21, ne
	lsr	x21, x21, #1
	ldr	w9, [x28, #G_AONLY]
	cbnz	w9, 1f
	ldr	x0, [x27, #E_VT]
	bl	nt_feed
1:	ldr	x0, [x27, #E_AT]
	bl	nt_feed
	ldr	w9, [x27, #E_HOLD]
	tbnz	w9, #1, Lnt_dry
	ldr	w10, [x28, #G_PLAYING]
	cmp	w9, #0
	ccmp	w10, #0, #4, eq
	b.eq	Lnt_again                 ; paused, or a seek waits
	cmp	x21, #STALL_LOW
	b.ge	Lnt_again
	orr	w9, w9, #2                ; dry: the clock holds
	str	w9, [x27, #E_HOLD]
	ldr	x0, [x27, #E_SYNC]
	movi	d0, #0
	SEND	S_setRate_
	b	Lnt_again
Lnt_dry:
	cmp	x21, #STALL_FULL
	b.lt	Lnt_again
	and	w9, w9, #~2
	str	w9, [x27, #E_HOLD]
	bl	Leng_rate
Lnt_again:
	ldr	w9, [x28, #G_PLAYING]
	ldr	x10, [x27, #E_VT]
	ldr	w11, [x27, #E_NET]
	orr	x10, x10, x11
	cmp	w9, #0
	ccmp	x10, #0, #4, ne
	cset	w1, eq                    ; paused: a tick a second, the picture fed freely until a playing tick
	str	w1, [x27, #E_SLOW]
	add	w1, w1, w1, lsl #1
	mov	w0, w19
	bl	Ltick_shift
	ldr	x19, [x27, #E_VT]
	cbz	x19, 1f
	bl	trk_request
1:	ldr	w9, [x27, #E_HOLD]
	ldr	x19, [x27, #E_AT]
	cmp	w9, #0
	ccmp	x19, #0, #4, eq
	b.eq	Lret2
	ldr	x0, [x27, #E_AR]
	SEND	S_isReadyForMoreMediaData
	cbz	w0, Lret2
	bl	trk_request
	b	Lret2

; tick_later(generation) — net_tick in an eighth of a second (Ltick_shift: shifted left by w1).
tick_later:
	mov	w1, #0
Ltick_shift:
	FRAME	1
	mov	w19, w0
	mov	w9, #(TICK_NS & 0xffff)
	movk	w9, #(TICK_NS >> 16), lsl #16
	lsl	w1, w9, w1
	mov	x0, #0
	bl	_dispatch_time
	ldr	x1, [x28, #G_MEDIAQ]
	mov	w2, w19
	adr	x3, net_tick
	bl	_dispatch_after_f
	b	Lret1

nt_feed:
	FRAME	1
	mov	x19, x0
	cbz	x19, 1f
	ldr	x0, [x19, #TR_ST]
	bl	st_pump
1:	mov	x0, x19
	bl	ahead_ms
	cmp	x0, x21
	csel	x21, x0, x21, lt          ; the least time queued ahead
	b	Lret1

; ahead_ms(track) -> x0 = ms of it queued past the clock (x20, ms); a large number with nothing more to come.
ahead_ms:
	mov	x9, #0x7fffffffffffffff
	cbz	x0, 1f
	ldr	x10, [x0, #TR_ST]
	cbz	x10, 1f
	ldr	w11, [x10, #ST_EOS]
	cbnz	w11, 1f
	ldr	x10, [x0, #TR_LAST]
	ldr	x11, [x0, #TR_TGT]
	cmp	x10, x11
	csel	x10, x10, x11, gt
	mov	x11, #1000
	mul	x10, x10, x11
	ldr	w11, [x0, #TR_TS]
	sdiv	x10, x10, x11
	sub	x9, x10, x20
1:	mov	x0, x9
	ret

; eng_tube(request) — YouTube on This Mac: its picture and sound streams; request = {generation, live, ms, picture URL, sound URL}, freed here (URLs become the streams').
	VMENTRY	eng_tube, Lp_tube
	.pushsection __DATA,__data
Lp_tube:
	NCALL	eng_close
	NCALL	hold, "I"
	.byte	0
	GL	0
	LDW	YT_GEN
	STEW	E_GEN
	GL	0
	LDX	YT_DUR
	STE	E_DURMS
	IMM	1
	STEW	E_NET
	STEW	E_ISO
	GL	0
	LDW	YT_LIVE
	SL	1
	STEW	E_LIVE
	GL	0
	LDX	YT_V
	SL	2
	JZ	Lp_tube_sound
	LW	G_AONLY
	EQ	0
	STEW	E_WANTV
	JNZ	Lp_tube_open
	GL	1
	JNZ	Lp_tube_open
	GL	2                         ; Audio Only: kept for later
	STE	E_ST + ST_URL
	JMP	Lp_tube_sound
	HERE	Lp_tube_open
	NCALL	st_open, "Bc"
	.short	E_ST
	GL	1
	JZ	Lp_tube_sound
	GL	0                         ; a broadcast's picture is its HLS, sound in it
	LDX	YT_A
	CALL	F_free, "V"
	JMP	Lp_tube_done
	HERE	Lp_tube_sound
	GL	0
	LDX	YT_A
	SL	3
	NCALL	st_open, "Bd"
	.short	E_ST + ST_SIZE
	HERE	Lp_tube_done
	CALL	F_free, "a"
	NCALL	await                     ; the clock held at 0 until the picture is ready
	LDEW	E_GEN
	NCALL	tick_later, "V"
	NCALL	post_main, "PI"
	.long	ui_poll - Lvm_base
	.byte	0
	OP_END
	.popsection

; eng_web(request) — any other web address on This Mac: one stream, its tracks as its movie box lists them; request = {generation, URL} like eng_open's.
	VMENTRY	eng_web, Lp_web
	.pushsection __DATA,__data
Lp_web:
	NCALL	eng_close
	NCALL	hold, "I"
	.byte	0
	GL	0
	LDW	0
	STEW	E_GEN
	IMM	1
	STEW	E_NET
	STEW	E_ISO
	STEW	E_WANTV                   ; until its tracks say otherwise
	GL	0
	ADDI	8
	CALL	F_strdup, "=V"
	SL	1
	CALL	F_free, "a"
	GL	1
	JZ	Lp_web_end
	NCALL	st_open, "Bb"
	.short	E_ST
	NCALL	await
	LDEW	E_GEN
	NCALL	tick_later, "V"
	NCALL	post_main, "PI"
	.long	ui_poll - Lvm_base
	.byte	0
	HERE	Lp_web_end
	OP_END
	.popsection

; ---- Actions (Objective-C methods: self, _cmd, sender) ----

; act_toggle — the play/pause button and Space.
	ENTRY	act_toggle
	b	local_toggle

; act_stop — Cmd-.
	ENTRY	act_stop
	b	local_stop

; act_back / act_fwd — the 10-second skips and Cmd-Left / Cmd-Right.
	ENTRY	act_back
	mov	x0, #-SKIP_SECONDS
	b	skip
	ENTRY	act_fwd
	mov	x0, #SKIP_SECONDS

; skip(delta) — seek from the position on screen and show the target at once, inside the track.
skip:
	VM	Lp_skip
	.pushsection __DATA,__data
Lp_skip:
	LD	G_POS
	MSG	S_isEnabled, ">"
	JZ	Lp_skip_end               ; unknown duration: nowhere to skip to
	LD	G_LTDUR
	SL	1
	LD	G_SHOWPOS
	ADDL	0
	SL	2
	GL	2
	SUBL	1
	LT	0
	JNZ	Lp_skip_low
	GL	1
	SL	2
	HERE	Lp_skip_low
	GL	2
	LT	1
	JZ	Lp_skip_go
	IMM	0
	SL	2
	HERE	Lp_skip_go
	NCALL	show_time, "cb"
	GL	2
	MULH	1000
	NCALL	seek_route, "V"
	HERE	Lp_skip_end
	OP_END
	.popsection

; seek_route(ms) — hold polled positions for the seek, then send it.
seek_route:
	ldr	x9, [x28, #G_TICK]
	add	x9, x9, #HOLD_TICKS
	str	x9, [x28, #G_SEEKH]
	b	local_seekms

; act_volup / act_voldown — Cmd-Up / Cmd-Down: one volume step.
	ENTRY	act_volup
	mov	w0, #VOLUME_STEP
	b	local_volstep
	ENTRY	act_voldown
	mov	w0, #-VOLUME_STEP
	b	local_volstep

; act_mute — the mute button and Opt-Cmd-Down.
	ENTRY	act_mute
	b	local_mute

; dragging() — w0 = 1 while the mouse button is still down.
dragging:
	VM	Lp_drag
	.pushsection __DATA,__data
Lp_drag:
	LD	G_APP
	MSG	S_currentEvent, "="
	MSG	S_type, "="               ; a nil event gives 0
	SL	0
	EQ	NSEventTypeLeftMouseDown
	JNZ	Lp_drag_end
	GL	0
	EQ	NSEventTypeLeftMouseDragged
	HERE	Lp_drag_end
	OP_END
	.popsection

; play_text(text) — resolve and play a link, search, web address or file path (copied); the newest one wins.
play_text:
	VM	Lp_text
	.pushsection __DATA,__data
Lp_text:
	GL	0
	LDB	0
	JZ	Lp_text_end               ; empty
	CALL	F_calloc, "=IX"
	.byte	1
	.long	JOB_SIZE
	JZ	Lp_text_end
	SL	1
	CALL	F_strdup, "=a"            ; the caller's text dies with its pool
	STX	1, JOB_QUERY
	JZ	Lp_text_drop
	LW	G_PLAYGEN
	ADDI	1
	SW	G_PLAYGEN
	STW	1, JOB_GEN
	IMM	1
	SW	G_LOADING
	LD	G_SPIN                    ; the spinner turns while it resolves
	MSG	S_startAnimation_, "I"
	.byte	0
	NCALL	set_status, "CI"
	.asciz	""
	.byte	0
	NCALL	stage_update
	GL	1
	LDX	JOB_QUERY                 ; a file needs no lookup: resolved here, at once
	SL	2
	LDB	0
	EQ	'/'
	JNZ	Lp_text_now
	CALL	F_strncmp, ">cCI"
	.asciz	"file://"
	.byte	7
	JNZ	Lp_text_later
	HERE	Lp_text_now
	NCALL	resolve, "=b"
	STW	1, JOB_RESULT
	NCALL	ui_play_done, "b"         ; already on main: no turn of the run loop to wait
	OP_END
	HERE	Lp_text_later
	CALL	F_dispatch_async_f, "ObP"
	.byte	G_WORKQ >> 3
	.long	play_resolve - Lvm_base
	OP_END
	HERE	Lp_text_drop
	CALL	F_free, "b"
	HERE	Lp_text_end
	OP_END
	.popsection

; play_url(url) — play an NSURL: a file by its path, anything else by its text.
play_url:
	VM	Lp_url
	.pushsection __DATA,__data
Lp_url:
	GL	0
	MSG	S_isFileURL, ">"
	JZ	Lp_url_web
	GL	0
	MSG	S_path, "="
	JMP	Lp_url_text
	HERE	Lp_url_web
	GL	0
	MSG	S_absoluteString, "="
	HERE	Lp_url_text
	MSG	S_UTF8String, "="
	JZ	Lp_url_end
	NCALL	play_text, "V"
	HERE	Lp_url_end
	OP_END
	.popsection

; act_play — Return in the link field: play what it holds.
	VMENTRY	act_play, Lp_play
	.pushsection __DATA,__data
Lp_play:
	CLS	NSCharacterSet
	MSG	S_whitespaceAndNewlineCharacterSet, "="
	SL	0
	LD	G_FIELD
	MSG	S_stringValue, "="
	MSG	S_stringByTrimmingCharactersInSet_, "=a"
	MSG	S_UTF8String, "="
	SL	0
	NCALL	url_hide
	GL	0
	JZ	Lp_play_1
	NCALL	play_text, "V"
	HERE	Lp_play_1
	OP_END
	.popsection

; act_focus — Open from URL (Cmd-L): the link field floats in, ready to paste.
	VMENTRY	act_focus, Lprog_focus

; url_hide() — the link field goes away and the window keeps the keyboard.
url_hide:
	VM	Lp_urlhide
	.pushsection __DATA,__data
Lp_urlhide:
	LD	G_URLBOX
	MSG	S_isHidden, ">"
	JNZ	Lp_urlhide_1                        ; already
	LD	G_URLBOX
	MSG	S_setHidden_, "I"
	.byte	1
	LD	G_WIN
	MSG	S_makeFirstResponder_, "O"
	.byte	G_CONTENT >> 3
	HERE	Lp_urlhide_1
	OP_END
	.popsection

; act_urlcmd(control, text view, command) -> YES for Escape, which closes the link field.
	ENTRY	act_urlcmd
	FRAME	0
	ldr	x9, [x27, #S_cancelOperation_]
	mov	w0, #0
	cmp	x4, x9
	b.ne	Lret0
	bl	url_hide
	mov	w0, #1
	b	Lret0

; act_open — Open (Cmd-O): pick an audio or video file.
	VMENTRY	act_open, Lp_open
	.pushsection __DATA,__data
Lp_open:
	CLS	UTType
	MSG	S_typeWithIdentifier_, "=S"
	.asciz	"public.audiovisual-content"
	SL	0
	CLS	NSArray
	MSG	S_arrayWithObject_, "=a"
	SL	0
	CLS	NSOpenPanel
	MSG	S_openPanel, "="
	SL	1
	MSG	S_setAllowedContentTypes_, "a"
	MSG	S_runModal, "="
	EQ	1                         ; NSModalResponseOK
	JZ	Lp_open_1
	GL	1
	MSG	S_URL, "="
	NCALL	play_url, "V"
	HERE	Lp_open_1
	OP_END
	.popsection

; act_openurls(app, urls) — files opened with MIA from the Finder or the Dock.
	VMENTRY	act_openurls, Lp_openurls
	.pushsection __DATA,__data
Lp_openurls:
	GL	3
	MSG	S_firstObject, "="
	JZ	Lp_openurls_1
	NCALL	play_url, "V"
	HERE	Lp_openurls_1
	OP_END
	.popsection

; act_drop(drag) -> YES when a dropped file, link or text was taken.
	VMENTRY	act_drop, Lp_drop
	.pushsection __DATA,__data
Lp_drop:
	GL	2
	MSG	S_draggingPasteboard, "="
	SL	2
	CLS	NSURL
	SL	3
	CLS	NSArray
	MSG	S_arrayWithObject_, "=d"
	SL	3
	GL	2
	MSG	S_readObjectsForClasses_options_, "=dI"
	.byte	0
	MSG	S_firstObject, "="
	JZ	Lp_drop_1
	NCALL	play_url, "V"
	IMM	1
	OP_END
	HERE	Lp_drop_1
	GL	2
	MSG	S_stringForType_, "=S"
	.asciz	"public.utf8-plain-text"
	MSG	S_UTF8String, "="
	JZ	Lp_drop_2
	NCALL	play_text, "V"
	IMM	1
	HERE	Lp_drop_2
	OP_END
	.popsection

; act_click(event) — a click on the stage closes the link field; a double click toggles full screen.
	VMENTRY	act_click, Lp_click
	.pushsection __DATA,__data
Lp_click:
	NCALL	url_hide
	GL	2
	MSG	S_clickCount, "="
	EQ	2
	JZ	Lp_click_1
	LD	G_WIN
	MSG	S_toggleFullScreen_, "I"
	.byte	0
	HERE	Lp_click_1
	OP_END
	.popsection

; act_moved(event) — the mouse moved: the controls come back, and note whether it is over them.
	VMENTRY	act_moved, Lp_moved
	.pushsection __DATA,__data
Lp_moved:
	IMM	0
	SW	G_IDLE
	GL	2
	MSG	S_locationInWindow, "^"   ; f: its height above the bottom
	FK	(BAR_M + BAR_H + 8) * 16
	FOP	6, 5                      ; over the bar
	SW	G_HOVER
	NCALL	bar_show
	OP_END
	.popsection

; act_aonly — Audio Only (the headphones and Opt-Cmd-A): no picture is fetched, decoded or shown.
	VMENTRY	act_aonly, Lp_aonly
	.pushsection __DATA,__data
Lp_aonly:
	LW	G_AONLY
	EQ	0
	SW	G_AONLY
	SL	0
	LD	G_AOITEM
	MSG	S_setState_, "a"
	LD	G_SECOND
	SL	1
	GL	0
	JZ	Lp_aonly_1
	LD	G_YEL
	SL	1
	HERE	Lp_aonly_1
	LD	G_AOBTN
	MSG	S_setContentTintColor_, "b"
	NCALL	eng_cmd, "PI"
	.long	eng_aonly - Lvm_base
	.byte	0
	NCALL	local_poll
	OP_END
	.popsection

; act_vol — the volume slider.
	VMENTRY	act_vol, Lp_vol
	.pushsection __DATA,__data
Lp_vol:
	LD	G_VOL
	MSG	S_intValue, ">"
	SL	0
	NCALL	dragging, "="
	SW	G_VOLDRAG
	LD	G_TICK
	ADDI	HOLD_TICKS
	STO	G_VOLH
	NCALL	local_setvol, "a"
	OP_END
	.popsection

; act_seek — the position slider: This Mac follows the drag frame by frame.
	VMENTRY	act_seek, Lp_aseek
	.pushsection __DATA,__data
Lp_aseek:
	LD	G_POS
	MSG	S_doubleValue, "^"
	FL	4
	FOPK	2, 16000                  ; to the millisecond
	FT
	SL	0
	LD	G_POS
	MSG	S_maxValue, "@"
	SL	1
	GL	0
	DIVH	1000
	NCALL	show_time, "Vb"
	NCALL	dragging, "="
	SW	G_SEEKDRAG
	JZ	Lp_aseek_rel
	NCALL	local_seekms, "a"
	OP_END
	HERE	Lp_aseek_rel
	NCALL	seek_route, "a"
	OP_END
	.popsection

; act_tick — the 1 Hz timer: the controls' idle fade; This Mac renders itself.
	VMENTRY	act_tick, Lp_tick
	.pushsection __DATA,__data
Lp_tick:
	LD	G_TICK
	ADDI	1
	STO	G_TICK
	NCALL	idle_tick
	NCALL	local_poll
	OP_END
	.popsection

; idle_tick() — a picture playing on This Mac: after a few still seconds the controls and the pointer fade away.
idle_tick:
	VM	Lp_idle
	.pushsection __DATA,__data
Lp_idle:
	LW	G_IDLE
	ADDI	1
	SW	G_IDLE
	LT	HIDE_TICKS
	JNZ	Lp_idle_1
	LW	G_BARHID
	JNZ	Lp_idle_1
	LW	G_HOVER
	JNZ	Lp_idle_1
	LW	G_AONLY
	JNZ	Lp_idle_1
	LW	G_HASVIDEO
	JZ	Lp_idle_1
	LW	G_PPSHOWN
	JZ	Lp_idle_1
	LD	G_URLBOX
	MSG	S_isHidden, ">"
	JZ	Lp_idle_1                        ; a link is being typed
	IMM	1
	SW	G_BARHID
	NCALL	bar_alpha, "D"
	.short	0
	CLS	NSCursor
	MSG	S_setHiddenUntilMouseMoves_, "I"
	.byte	1
	HERE	Lp_idle_1
	OP_END
	.popsection

; act_key(event) — keys on the stage: Space plays and pauses, arrows skip and change the volume, F toggles full screen (Escape leaves it), M mutes.
	VMENTRY	act_key, Lp_key
	.pushsection __DATA,__data
Lp_key:
	GL	2
	MSG	S_keyCode, ">"
	SL	3
	EQ	49                        ; Space
	JNZ	Lp_key_toggle
	GL	3
	EQ	123                       ; left
	JNZ	Lp_key_back
	GL	3
	EQ	124                       ; right
	JNZ	Lp_key_fwd
	GL	3
	EQ	126                       ; up
	JNZ	Lp_key_up
	GL	3
	EQ	125                       ; down
	JNZ	Lp_key_down
	GL	3
	EQ	46                        ; M
	JNZ	Lp_key_mute
	GL	3
	EQ	3                         ; F
	JNZ	Lp_key_full
	GL	3
	EQ	53                        ; Escape: only in full screen
	JZ	Lp_key_end
	LD	G_WIN
	MSG	S_styleMask, "="
	BIT	14
	JZ	Lp_key_end
	HERE	Lp_key_full
	LD	G_WIN
	MSG	S_toggleFullScreen_, "I"
	.byte	0
	OP_END
	HERE	Lp_key_toggle
	NCALL	Lact_toggle
	OP_END
	HERE	Lp_key_back
	NCALL	Lact_back
	OP_END
	HERE	Lp_key_fwd
	NCALL	Lact_fwd
	OP_END
	HERE	Lp_key_up
	NCALL	Lact_volup
	OP_END
	HERE	Lp_key_down
	NCALL	Lact_voldown
	OP_END
	HERE	Lp_key_mute
	NCALL	Lact_mute
	HERE	Lp_key_end
	OP_END
	.popsection

; act_speed(item) — Playback > Speed: This Mac plays at the item's tag / 100, now and after.
	VMENTRY	act_speed, Lp_speed
	.pushsection __DATA,__data
Lp_speed:
	GL	2
	MSG	S_tag, "="
	SL	4
	GL	2                         ; the checkmark moves to it
	MSG	S_menu, "="
	MSG	S_itemArray, "="
	SL	5
	MSG	S_count, "="
	SL	6
	HERE	Lp_speed_mark
	GL	6
	ADDI	-1
	SL	6
	LT	0
	JNZ	Lp_speed_rate
	GL	5
	MSG	S_objectAtIndex_, "=g"
	SL	7
	EQL	2
	SL	3
	GL	7
	MSG	S_setState_, "d"
	JMP	Lp_speed_mark
	HERE	Lp_speed_rate
	NCALL	speed_rate, "e"
	OP_END
	.popsection

; speed_rate(percent) — This Mac plays at percent / 100, now and after.
speed_rate:
	FRAME	0
	scvtf	s0, w0
	mov	w9, #100
	scvtf	s1, w9
	fdiv	s0, s0, s1
	str	s0, [x28, #G_RATE]
	adr	x0, eng_rate
	mov	x1, #0
	bl	eng_cmd
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_setDefaultRate_         ; play uses it from now on
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_timeControlStatus
	cbz	x0, Lret0                 ; paused: it stays paused
	ldr	s0, [x28, #G_RATE]
	ldr	x0, [x28, #G_PLAYER]
	SEND	S_setRate_
	b	Lret0

; media_group(kind) -> This Mac's item's subtitles (0) or sound tracks (1), or nil.
media_group:
	VM	Lp_group
	.pushsection __DATA,__data
Lp_group:
	LD	G_PLAYER
	MSG	S_currentItem, "="
	MSG	S_asset, "="
	SL	1
	GL	0
	JNZ	Lp_group_sound
	GL	1
	MSG	S_mediaSelectionGroupForMediaCharacteristic_, "=S"
	.asciz	"AVMediaCharacteristicLegible"
	OP_END
	HERE	Lp_group_sound
	GL	1
	MSG	S_mediaSelectionGroupForMediaCharacteristic_, "=S"
	.asciz	"AVMediaCharacteristicAudible"
	OP_END
	.popsection

; act_options(menu) — View > Subtitles and Audio Track as they open: the tracks, the chosen one checked.
	VMENTRY	act_options, Lp_options
	.pushsection __DATA,__data
Lp_options:
	GL	2
	MSG	S_removeAllItems
	LW	G_MODE
	JNZ	Lp_options_av
	LD	G_MEDIAQ                  ; the engine's own, read while its queue waits
	SL	0
	CALL	F_dispatch_sync_f, "acP"
	.long	eng_options - Lvm_base
	OP_END
	HERE	Lp_options_av
	GL	2
	EQS	G_SUBMENU
	EQ	0
	SL	3                         ; d: 0 subtitles, 1 sound tracks
	NCALL	media_group, "=d"
	SL	4                         ; e: the group
	IMM	0
	SL	5                         ; f: the chosen option
	GL	4
	JZ	Lp_options_none
	LD	G_PLAYER
	MSG	S_currentItem, "="
	MSG	S_currentMediaSelection, "="
	MSG	S_selectedMediaOptionInMediaSelectionGroup_, "=e"
	SL	5
	HERE	Lp_options_none
	GL	5
	EQ	0
	SL	6
	GL	3
	JNZ	Lp_options_sound
	NCALL	opt_item, "cCJg"          ; subtitles can be off; a sound track cannot
	.asciz	"Off"
	.byte	-1
	JMP	Lp_options_list
	HERE	Lp_options_sound
	NCALL	opt_item, "=cCJg"
	.asciz	"Default"
	.byte	-1
	MSG	S_setEnabled_, "I"        ; with one sound track there is nothing to choose
	.byte	0
	HERE	Lp_options_list
	GL	4
	JZ	Lp_options_end
	MSG	S_options, "="
	SL	4                         ; e: the options
	MSG	S_count, "="
	SL	7                         ; h: their count
	IMM	0
	SL	6                         ; g: the index
	HERE	Lp_options_each
	GL	6
	EQL	7
	JNZ	Lp_options_end
	GL	4
	MSG	S_objectAtIndex_, "=g"
	SL	1
	MSG	S_displayName, "="
	MSG	S_UTF8String, "="
	SL	0
	GL	1
	EQL	5
	SL	3
	NCALL	opt_item, "cagd"
	GL	6
	ADDI	1
	SL	6
	JMP	Lp_options_each
	HERE	Lp_options_end
	OP_END
	.popsection

; opt_item(menu, title, tag, on) -> x0 = an option for act_option, checked when on.
opt_item:
	VM	Lp_optitem
	.pushsection __DATA,__data
Lp_optitem:
	NCALL	mkstr, "=b"
	SL	1
	GL	0
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=bES"
	.short	S_act_option_
	.asciz	""                        ; no key
	SL	4
	MSG	S_setTag_, "c"
	GL	4
	MSG	S_setState_, "d"
	GL	4
	OP_END
	.popsection

; eng_options(menu) — the engine's subtitle or sound tracks as options, named by language (on main, the media queue waiting).
	.pushsection __DATA,__data
Ls_off:	.asciz	"Off"
Ls_trackn:	.asciz	"Track "
Ls_tcc:	.asciz	"TYPE=CLOSED-CAPTIONS"
Ls_cc1:	.asciz	"\"CC1\""
	.popsection
	VMTENTRY	eng_options
	IMM	'a'
	SL	2                         ; c: the kind listed
	LDE	E_AT
	SL	1                         ; b: the one playing
	GL	0
	EQS	G_SUBMENU
	JZ	Leo_kind
	IMM	's'
	SL	2
	LDE	E_SUBT
	SL	1
	EQ	0
	SL	7
	NCALL	opt_item, "aPJh"          ; subtitles can be off
	.long	Ls_off - Lvm_base
	.byte	0xff
	HERE	Leo_kind
	LDE	E_MASTER
	JNZ	Leo_hlsj
	IMM	0
	SL	3                         ; d: the track's index
	SL	4                         ; e: its number in the list
	HERE	Leo_each
	GL	3
	LT	TRACKS
	JZ	Leo_end1                  ; the slots past the tracks read are empty
	GL	3
	SHL	9
	SL	5
	LEAB	E_TR
	ADDL	5
	SL	5                         ; f: the track (TR_SIZE 512)
	LDW	TR_KIND
	EQL	2
	JZ	Leo_next
	GL	4
	ADDI	1
	SL	4
	GL	5
	ADDH	TR_LANG
	SL	6                         ; g: its language's three letters
	LDB	0
	JZ	Leo_num
	NCALL	mkstr, "=g"
	SL	7
	CLS	NSLocale
	MSG	S_currentLocale, "="
	MSG	S_localizedStringForLanguageCode_, "=h"
	JZ	Leo_num
	MSG	S_UTF8String, "="
	SL	6
	JMP	Leo_item
	HERE	Leo_num
	LEAB	B_UJ                      ; no language: its number, in the media queue's scratch (it waits); one digit (TRACKS 8)
	SL	6
	CALL	F_strlcpy, "gPI"
	.long	Ls_trackn - Lvm_base
	.byte	16
	GL	4
	ADDI	'0'
	STW	6, 6
	HERE	Leo_item
	GL	1
	EQL	5
	SL	7
	NCALL	opt_item, "agdh"
	HERE	Leo_next
	GL	3
	ADDI	1
	SL	3
	JMP	Leo_each
	HERE	Leo_end1
	OP_END
	HERE	Leo_hlsj
	LEAB	E_ST + ST_SIZE            ; HLS: the master's renditions, by NAME; the one its stream plays checked
	SL	6
	GL	2
	EQ	's'
	SL	5                         ; f: subtitles
	JZ	Leo_h1
	LEAB	E_ST + 2 * ST_SIZE
	SL	6
	HERE	Leo_h1
	GL	6
	LDX	ST_PLURL
	SL	1                         ; b: the playing rendition's playlist
	IMM	0
	SL	4                         ; e: its group, for its siblings (none: every one)
	GL	5
	JNZ	Leo_list
	LDE	E_MASTER
	HERE	Leo_find
	NCALL	media_next, "?VP"
	.long	Ls_taudio - Lvm_base
	JZ	Leo_end2                  ; none playing: nothing to choose
	SL	6                         ; g, h: its line
	NCALL	uri_is, "ghIb"
	.byte	0
	JNZ	Leo_grp
	LDE	B_MNEXT
	JMP	Leo_find
	HERE	Leo_grp
	NCALL	attr, "?ghP"
	.long	Ls_group - Lvm_base
	SL	4                         ; e, f: its group
	GL	7
	SL	5
	HERE	Leo_list
	IMM	16
	SHL	8
	SL	3                         ; d: the rendition's tag, 0x1000 + its index
	LDE	E_MASTER
	HERE	Leo_rend
	SL	6
	GL	2
	EQ	's'
	JZ	Leo_ra
	GL	6
	NCALL	media_next, "?VP"
	.long	Ls_tsubs - Lvm_base
	JMP	Leo_rgot
	HERE	Leo_end2
	OP_END
	HERE	Leo_ra
	GL	6
	NCALL	media_next, "?VP"
	.long	Ls_taudio - Lvm_base
	HERE	Leo_rgot
	JZ	Leo_ccj
	SL	6                         ; g, h: the line
	GL	4
	JZ	Leo_rok                   ; no group to match
	GL	6                         ; the line kept: attr gives the group's span in its place
	STE	B_UJ + 80
	GL	7
	STE	B_UJ + 64
	NCALL	attr, "?ghP"
	.long	Ls_group - Lvm_base
	JZ	Leo_rskip
	SL	6
	GL	7
	SUBL	6
	SL	7                         ; its length
	GL	5
	SUBL	4
	EQL	7
	JZ	Leo_rskip
	CALL	F_strncmp, "=geh"
	JNZ	Leo_rskip                 ; another group
	LDE	B_UJ + 80
	SL	6
	LDE	B_UJ + 64
	SL	7
	HERE	Leo_rok
	NCALL	uri_is, "ghIb"
	.byte	0
	NCALL	opt_named, "ghadV"
	HERE	Leo_rskip
	GL	3
	ADDI	1
	SL	3
	LDE	B_MNEXT
	JMP	Leo_rend
	HERE	Leo_ccj
	GL	2                         ; subtitles: then the captions in the picture (CC1 only), tagged 0x2000 + their index
	EQ	's'
	JZ	Leo_end3
	IMM	32
	SHL	8
	SL	3
	LDE	E_MASTER
	HERE	Leo_ccn
	NCALL	media_next, "?VP"
	.long	Ls_tcc - Lvm_base
	JZ	Leo_end3
	SL	6
	GL	7
	SUBL	6
	SL	5
	CALL	F_strnstr, "=gPf"
	.long	Ls_cc1 - Lvm_base
	JZ	Leo_ccskip
	LDE	E_CCT
	SL	4
	JZ	Leo_ccon                  ; on: its track made and shown
	LDE	E_SUBT
	EQL	4
	HERE	Leo_ccon
	NCALL	opt_named, "ghadV"
	HERE	Leo_ccskip
	GL	3
	ADDI	1
	SL	3
	LDE	B_MNEXT
	JMP	Leo_ccn
	HERE	Leo_end3
	OP_END
	.p2align 2

; opt_named(line, end, menu, tag, on) — an option titled by the line's NAME (none: no option).
	.pushsection __DATA,__data
Ls_name:	.asciz	"NAME="
	.popsection
opt_named:
	VMT
	NCALL	attr, "?abP"
	.long	Ls_name - Lvm_base
	JZ	Lon_end
	SL	5                         ; f: the name, h: its end
	GL	7
	SUBL	5
	SL	6                         ; g: its length, at most 47
	LT	47
	JNZ	Lon_len
	IMM	47
	SL	6
	HERE	Lon_len
	LEAB	B_UJ                      ; the media queue's scratch: it waits while the menu is made
	SL	7
	CALL	F_memcpy, "hfg"
	GL	7
	ADDL	6
	SL	5
	IMM	0
	STW	5, 0
	NCALL	opt_item, "chde"
	HERE	Lon_end
	OP_END
	.p2align 2

; txt_fd(track) — the track's format: tx3g text cues.
txt_fd:
	add	x4, x0, #TR_FD
	mov	x0, #0
	mov	w1, #0x3367
	movk	w1, #0x7478, lsl #16
	mov	w2, w1
	mov	x3, #0
	b	_CMFormatDescriptionCreate

; cc_track -> x0 = the CC1 caption track, made once: fed from the picture's SEI, read from its queue.
cc_track:
	FRAME	1
	ldr	x0, [x27, #E_CCT]
	cbnz	x0, Lret1
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lret1
	add	w10, w9, #1
	str	w10, [x27, #E_NTR]
	BADDR	x19, E_TR
	add	x19, x19, x9, lsl #9
	mov	w9, #'s'
	mov	w10, #(90000 & 0xffff)
	movk	w10, #(90000 >> 16), lsl #16
	stp	w9, w10, [x19, #TR_KIND]
	mov	w9, #1
	str	w9, [x19, #TR_SRC]
	BADDR	x9, E_ST
	str	x9, [x19, #TR_ST]
	mov	x0, #(FIFO_N * 8)
	bl	_malloc
	str	x0, [x19, #TR_FQ]
	cbz	x0, Lret1
	mov	x0, x19
	bl	txt_fd
	str	x19, [x27, #E_CCT]
	mov	x0, x19
	b	Lret1

; media_next(p, type) -> x0 = the next #EXT-X-MEDIA line from p with that TYPE=..., x1 = its end, x2 = the line after it; x0 = 0 at the end.
media_next:
	FRAME	3, 0, 1
Lmx_line:
	ldrb	w9, [x19]
	cbz	w9, Lmx_none
	mov	x0, x19
	bl	line_end
	mov	x21, x0
	mov	x22, x1
	mov	x0, x19
	GADDR	x1, Ls_xmedia
	mov	x2, #13
	bl	_strncmp
	cbnz	w0, Lmx_next
	mov	x0, x19
	mov	x1, x20
	sub	x2, x21, x19
	bl	_strnstr
	cbnz	x0, Lmx_found
Lmx_next:
	mov	x19, x22
	b	Lmx_line
Lmx_found:
	str	x22, [x27, #B_MNEXT]
	mov	x0, x19
	mov	x1, x21
	mov	x2, x22
	b	Lret3
Lmx_none:
	mov	x0, #0
	b	Lret3

; uri_is(line, end, url) -> w0 = 1 if the URL (0: none) ends with the line's URI.
uri_is:
	FRAME	2
	mov	x19, x3
	mov	w20, #0
	cbz	x19, 1f
	GADDR	x2, Ls_uri
	bl	attr
	cbz	x0, 1f
	mov	x21, x0
	sub	x22, x1, x0
	mov	x0, x19
	bl	_strlen
	subs	x0, x0, x22
	b.lo	1f
	add	x0, x19, x0
	mov	x1, x21
	mov	x2, x22
	bl	_memcmp
	cmp	w0, #0
	cset	w20, eq
1:	mov	w0, w20
	b	Lret2

; eng_pick(choice) — a track picked: subtitles (index, -1 none) or, with bit 32, a sound track of the file, or an HLS rendition (0x1000 + its index); it plays from now.
	ENTRY	eng_pick
	FRAME	2
	mov	x20, x0
	BADDR	x0, (E_ST + 2 * ST_SIZE)  ; a subtitle rendition's stream stops
	tbnz	x20, #32, 2f
	bl	st_close
2:	mov	x0, x20
	mov	x19, #0
	tbnz	w0, #31, 1f
	cmp	w0, #0x1000
	b.hs	Lpk_hls
	ldr	w9, [x27, #E_NTR]
	cmp	w0, w9
	b.hs	Lret2                     ; other media now
	BADDR	x19, E_TR
	mov	w9, w0
	add	x19, x19, x9, lsl #9
	ldr	w9, [x19, #TR_KIND]
	mov	w10, #'s'
	mov	w11, #'a'
	tst	x0, #(1 << 32)
	csel	w10, w11, w10, ne
	cmp	w9, w10
	b.ne	Lret2
1:	tbnz	x0, #32, Lpk_sound
	str	x19, [x27, #E_SUBT]
	bl	now_ms
	bl	sub_seek
	b	Lret2
Lpk_sound:
	ldr	x9, [x27, #E_AT]
	ldr	w10, [x19, #TR_SRC]
	cmp	x9, x19
	ccmp	w10, #0, #0, ne           ; a stream's track stays with its stream
	b.ne	Lret2
	str	x19, [x27, #E_AT]
	bl	now_ms
	mov	x3, x0
	mov	x0, x19
	ldr	x1, [x27, #E_AR]
	ADDR	x2, Lblk_a
	bl	trk_play
	b	Lret2
Lpk_hls:
	cmp	w20, #0x2000
	b.lo	1f
	bl	cc_track                  ; CC1: the picture's captions from now
	cbz	x0, Lret2
	str	x0, [x27, #E_SUBT]
	bl	now_ms
	bl	sub_seek
	b	Lret2
1:	ldr	x19, [x27, #E_MASTER]
	cbz	x19, Lret2
	GADDR	x1, Ls_taudio
	GADDR	x9, Ls_tsubs
	tst	x20, #(1 << 32)
	csel	x21, x1, x9, ne
	and	w22, w20, #0xfff          ; the index-th of its type
1:	mov	x0, x19
	mov	x1, x21
	bl	media_next
	cbz	x0, Lret2                 ; other media now
	mov	x19, x2
	subs	w22, w22, #1
	b.hs	1b
	GADDR	x2, Ls_uri
	bl	attr
	cbz	x0, Lret2
	mov	x2, x1
	mov	x1, x0
	ldr	x0, [x27, #E_MURL]
	bl	url_join
	cbz	x0, Lret2
	mov	x21, x0                   ; its playlist
	tbnz	x20, #32, Lpk_hsound
	BADDR	x19, (E_ST + 2 * ST_SIZE) ; subtitles: their own stream feeds the shown track
	ldr	x22, [x19, #ST_TR]
	cbnz	x22, 2f
	mov	x0, x19
	mov	w1, #'s'
	mov	w2, #1000                 ; ms
	bl	trk_new
	mov	x22, x0
	cbz	x0, Lpk_free
	mov	x0, x22                   ; its cues come as tx3g samples
	bl	txt_fd
2:	mov	x0, x19
	mov	x1, x21
	bl	pl_set
	str	x22, [x27, #E_SUBT]
	bl	now_ms
	mov	x20, x0
	bl	sub_seek
	mov	x0, x19
	mov	x1, x20
	bl	st_seek
	b	Lret2
Lpk_hsound:
	ldr	x0, [x27, #E_AR]          ; sound: the rendition's stream from now, the old sound dropped
	SEND	S_stopRequestingMediaData
	ldr	x0, [x27, #E_AR]
	SEND	S_flush
	BADDR	x19, (E_ST + ST_SIZE)
	mov	x0, x19
	mov	x1, x21
	bl	pl_set
	bl	now_ms
	mov	x1, x0
	mov	x0, x19
	bl	st_seek
	b	Lret2
Lpk_free:
	mov	x0, x21
	bl	_free
	b	Lret2

; act_option(item) — a subtitle or sound track picked: This Mac's item switches to it (tag -1: subtitles off).
	VMENTRY	act_option, Lp_option
	.pushsection __DATA,__data
Lp_option:
	GL	2
	MSG	S_menu, "="
	EQS	G_SUBMENU
	EQ	0
	SL	3                         ; d: 0 subtitles, 1 sound tracks
	GL	2
	MSG	S_tag, ">"
	SL	4                         ; e: the tag's word
	LW	G_MODE
	JNZ	Lp_option_av
	GL	3                         ; the engine's: picked on its queue, the kind in bit 32
	SHL	32
	ADDL	4
	SL	5
	NCALL	eng_cmd, "Pf"
	.long	eng_pick - Lvm_base
	OP_END
	HERE	Lp_option_av
	NCALL	media_group, "=d"
	JZ	Lp_option_end
	SL	6                         ; g: the group
	IMM	0
	SL	7                         ; h: the option, none for subtitles off
	GL	4
	BIT	31
	JNZ	Lp_option_pick
	GL	6
	MSG	S_options, "="
	MSG	S_objectAtIndex_, "=e"
	SL	7
	HERE	Lp_option_pick
	LD	G_PLAYER
	MSG	S_currentItem, "="
	MSG	S_selectMediaOption_inMediaSelectionGroup_, "hg"
	HERE	Lp_option_end
	OP_END
	.popsection

; act_pip — View > Picture in Picture (Opt-Cmd-P): This Mac's picture floats in its own window, and comes back.
	VMENTRY	act_pip, Lp_pip
	.pushsection __DATA,__data
Lp_pip:
	LW	G_MODE
	JNZ	Lp_pip_av
	LDE	B_PIPE                    ; the engine's picture: its sample buffer layer, played through this controller's PiP methods
	JNZ	Lp_pip_toggle
	CLS	AVPictureInPictureControllerContentSource
	MSG	S_alloc, "="
	MSG	S_initWithSampleBufferDisplayLayer_playbackDelegate_, "=OO"
	.byte	G_SBLAYER >> 3, G_CTRL >> 3
	SL	0
	CLS	AVPictureInPictureController
	MSG	S_alloc, "="
	MSG	S_initWithContentSource_, "=a"
	STE	B_PIPE
	JMP	Lp_pip_made
	HERE	Lp_pip_av
	LD	G_PIP
	JNZ	Lp_pip_toggle
	LD	G_VIDEO
	MSG	S_layer, "="
	SL	0
	CLS	AVPictureInPictureController
	MSG	S_alloc, "="
	MSG	S_initWithPlayerLayer_, "=a"
	STO	G_PIP
	HERE	Lp_pip_made
	JZ	Lp_pip_end
	HERE	Lp_pip_toggle
	SL	0
	MSG	S_isPictureInPictureActive, ">"
	JNZ	Lp_pip_stop
	GL	0
	MSG	S_startPictureInPicture
	OP_END
	HERE	Lp_pip_stop
	GL	0
	MSG	S_stopPictureInPicture
	HERE	Lp_pip_end
	OP_END
	.popsection

; pip_play(self, _cmd, controller, playing) — PiP's play button: This Mac plays or pauses.
	ENTRY	pip_play
	ldr	w9, [x28, #G_PLAYING]
	cmp	w9, w3
	b.ne	local_toggle
	ret

; pip_range(self, _cmd, controller) -> CMTimeRange (x8): the media's length, endless when unknown or live.
	ENTRY	pip_range
	ldr	x9, [x27, #E_DURMS]
	mov	x10, #1000
	movk	x10, #1, lsl #32          ; ms, valid
	stp	xzr, x10, [x8]
	str	xzr, [x8, #16]
	mov	x11, #(5 << 32)           ; valid, +infinity
	cmp	x9, #0
	csel	x10, x10, x11, ne
	stp	x9, x10, [x8, #24]
	str	xzr, [x8, #40]
	ret

; pip_paused(self, _cmd, controller) -> w0 = This Mac is paused.
	ENTRY	pip_paused
	ldr	w0, [x28, #G_PLAYING]
	eor	w0, w0, #1
	ret

; pip_skip(self, _cmd, controller, interval, handler) — PiP's skip buttons: a seek by the interval, then the handler.
	ENTRY	pip_skip
	FRAME	1
	mov	x19, x4
	ldr	x9, [x3]
	ldrsw	x10, [x3, #8]
	mov	x11, #1000
	mul	x9, x9, x11
	sdiv	x20, x9, x10
	bl	now_ms
	adds	x0, x0, x20
	csel	x0, x0, xzr, gt
	bl	local_seekms
	ldr	x16, [x19, #16]
	mov	x0, x19
	blr	x16
	b	Lret1

; act_layout — the window was resized (or went full screen).
	ENTRY	act_layout
	b	layout_stage

; imp_yes -> YES: the last window closing quits; the canvas takes the keyboard; a drag is a copy.
imp_yes:
	mov	w0, #1
	ret

; ---- Construction ----

; ---- Entry point ----

; main() — the registry, then services, the app with its menus and window and the poll timer; then the run loop.
	.private_extern	_main
_main:
	FRAME	0, 128                    ; a name, spelled out
	ADDR	x19, Ldl
	ldr	x21, [x19]                ; dlsym, the one import
	mov	x0, #-2                   ; RTLD_DEFAULT
	ADDR	x1, Ls_calloc
	blr	x21
	mov	x9, x0
	mov	x0, #1
	mov	x1, #GB_SIZE
	blr	x9
	mov	x28, x0
	add	x27, x0, #((G_SIZE + 15) & ~15)
	stp	x28, x27, [x19, #8]
	mov	x0, #-2
	ADDR	x1, Ls_dlopen
	blr	x21
	mov	x9, x0
	ADDR	x0, Ls_avkit              ; with AVFoundation and AppKit
	mov	w1, #9                    ; RTLD_LAZY | RTLD_GLOBAL
	blr	x9
	ADDR	x19, Lreg_names
	BADDR	x20, B_REG
	mov	x22, sp
Lmn_reg:
	ldrb	w9, [x19]
	cbz	w9, Lmn_regged
	mov	x10, sp
Lmn_char:
	ldrb	w9, [x19], #1
	tbnz	w9, #7, Lmn_word
	strb	w9, [x10], #1
	cbnz	w9, Lmn_char
	cmp	sp, x22                   ; a word's end: on after it
	b.ne	Lmn_back
	mov	x0, sp
	BADDR	x9, B_SEL
	cmp	x20, x9
	b.hs	Lmn_sel
	BADDR	x9, B_CLS
	cmp	x20, x9
	b.hs	Lmn_cls
	mov	x1, sp
	mov	x0, #-2                   ; RTLD_DEFAULT
	blr	x21
	b	Lmn_store
Lmn_cls:
	CALLF	objc_getClass
	b	Lmn_store
Lmn_sel:
	bl	_sel_registerName
Lmn_store:
	str	x0, [x20], #8
	b	Lmn_reg
Lmn_word:
	str	x19, [sp, #-16]!          ; past n words, then the word, itself spelled with words
	ADDR	x19, Lreg_words
	and	w9, w9, #0x7f
1:	cbz	w9, Lmn_char
	ldrb	w12, [x19], #1
	cbnz	w12, 1b
	sub	w9, w9, #1
	b	1b
Lmn_back:
	sub	x10, x10, #1
	ldr	x19, [sp], #16
	b	Lmn_char
Lmn_regged:
	ldr	x9, [x27, #F__NSConcreteGlobalBlock]
	ADDR	x10, Lblk_v
	str	x9, [x10]
	str	x9, [x10, #(Lblk_a - Lblk_v)]
	str	x9, [x10, #(Lblk_s - Lblk_v)]
	mov	w9, #100
	str	w9, [x28, #G_VOLPCT]
	fmov	d0, #1.0
	str	d0, [x28, #G_ARTASP]      ; a square card until artwork arrives
	fmov	s0, #1.0
	str	s0, [x28, #G_RATE]
	ADDR	x0, Lprog_build
	bl	ui_run
	ADDR	x0, Lprog_show
	bl	ui_run
	ADDR	x0, Lprog_stage
	bl	ui_run
	bl	local_poll
	bl	layout_stage
	adr	x0, eng_init
	mov	x1, #0
	bl	eng_cmd
	ADDR	x0, Lprog_run
	bl	ui_run
	mov	w0, #0
	b	Lret0

; ---- Matroska and WebM: blocks read in place from the mapped file, like MP4's samples ----

; el_head(p, end) -> x0 = an EBML element's data, x1 = its end (cut to end; an unknown size runs to it), w2 = its ID, x3 = its size (-1 unknown); x0 = 0 if the header does not fit.
el_head:
	cmp	x0, x1
	b.hs	Leh_no
	ldrb	w9, [x0]
	clz	w10, w9
	sub	w10, w10, #23             ; the ID's length, 1-4
	cmp	w10, #4
	b.hi	Leh_no
	add	x11, x0, x10
	cmp	x11, x1
	b.hs	Leh_no                    ; and a size byte after it
	mov	w2, #0
1:	ldrb	w9, [x0], #1
	orr	w2, w9, w2, lsl #8
	cmp	x0, x11
	b.lo	1b
	ldrb	w9, [x0], #1
	clz	w10, w9
	sub	w10, w10, #23             ; the size's length, 1-8
	cmp	w10, #8
	b.hi	Leh_no
	sub	x11, x0, #1
	add	x11, x11, x10
	cmp	x11, x1
	b.hi	Leh_no
	mov	w12, #0xff
	lsr	w12, w12, w10
	and	w3, w9, w12               ; the length's mark cleared
2:	cmp	x0, x11
	b.hs	3f
	ldrb	w9, [x0], #1
	orr	x3, x9, x3, lsl #8
	b	2b
3:	mov	w12, #7
	mul	w12, w12, w10
	mov	x13, #1
	lsl	x13, x13, x12
	sub	x13, x13, #1
	cmp	x3, x13
	b.ne	4f
	mov	x3, #-1                   ; all ones: unknown
	ret
4:	sub	x13, x1, x0
	cmp	x3, x13
	b.hi	5f
	add	x1, x0, x3
5:	ret
Leh_no:
	mov	x0, #0
	ret

; el_find(p, end, id) -> x0 = the data of the first element with that ID, x1 = its end; 0 if none.
el_find:
	mov	x16, x30
	mov	w4, w2
	mov	x5, x1
1:	mov	x1, x5
	bl	el_head
	cbz	x0, 2f
	cmp	w2, w4
	b.eq	2f
	mov	x0, x1
	b	1b
2:	mov	x30, x16
	ret

; el_num(p, end, id, default) -> x0 = that element's unsigned number, or default.
el_num:
	mov	x17, x30
	mov	x6, x3
	bl	el_find
	mov	x30, x17
	cbnz	x0, el_uint
	mov	x0, x6
	ret

; el_uint(p, end) -> x0 = the big-endian unsigned number from p to end.
el_uint:
	mov	x9, x0
	mov	x0, #0
1:	cmp	x9, x1
	b.hs	2f
	ldrb	w10, [x9], #1
	orr	x0, x10, x0, lsl #8
	b	1b
2:	ret

; el_float(p, end, id) -> d0 = that element's number (4 or 8 bytes), 0 if none.
el_float:
	mov	x17, x30
	bl	el_find
	mov	x30, x17
	movi	d0, #0
	cbz	x0, 2f
	sub	x9, x1, x0
	cmp	x9, #4
	b.ne	1f
	ldr	w9, [x0]
	rev	w9, w9
	fmov	s0, w9
	fcvt	d0, s0
	ret
1:	cmp	x9, #8
	b.ne	2f
	ldr	x9, [x0]
	rev	x9, x9
	fmov	d0, x9
2:	ret

; vint(p, end) -> x0 = the number at p (1-8 bytes, the length's mark cleared), x1 = past it, w2 = its length; x1 > end if it does not fit.
vint:
	cmp	x0, x1
	b.hs	3f
	ldrb	w9, [x0], #1
	clz	w2, w9
	sub	w2, w2, #23
	cmp	w2, #8
	b.hi	3f
	mov	w12, #0xff
	lsr	w12, w12, w2
	and	w11, w9, w12
	sub	x12, x0, #1
	add	x12, x12, x2
	cmp	x12, x1
	b.hi	3f
1:	cmp	x0, x12
	b.hs	2f
	ldrb	w9, [x0], #1
	orr	x11, x9, x11, lsl #8
	b	1b
2:	mov	x0, x11
	mov	x1, x12
	ret
3:	add	x1, x1, #1
	mov	x0, #0
	ret

; vsint(p, end) -> x0 = the signed number at p (EBML lacing's size differences), x1 = past it.
vsint:
	mov	x17, x30
	bl	vint
	mov	x30, x17
	mov	w9, #7
	mul	w9, w9, w2
	sub	w9, w9, #1
	mov	x10, #1
	lsl	x10, x10, x9
	sub	x10, x10, #1
	sub	x0, x0, x10
	ret

; xiph(p, end) -> x0 = a Xiph lace size at p (bytes added up to one under 255), x1 = past it; x1 > end if cut short.
xiph:
	mov	x9, x0
	mov	x0, #0
1:	cmp	x9, x1
	b.hs	2f
	ldrb	w10, [x9], #1
	add	x0, x0, x10
	cmp	w10, #255
	b.eq	1b
	mov	x1, x9
	ret
2:	add	x1, x1, #1
	ret

; el_resync(p, end) -> x0 = where the next top-level element's ID is (a Cluster, Cues, Info...), 0 if none.
el_resync:
	adr	x10, Lmk_top
1:	add	x11, x0, #4
	cmp	x11, x1
	b.hi	4f
	ldrb	w9, [x0]
	and	w9, w9, #0xf0
	cmp	w9, #0x10
	b.ne	3f
	ldr	w9, [x0]
	mov	x12, x10
2:	ldr	w13, [x12], #4
	cbz	w13, 3f
	cmp	w9, w13
	b.ne	2b
	ret
3:	add	x0, x0, #1
	b	1b
4:	mov	x2, x0
	mov	x0, #0
	ret
Lmk_top:                                  ; as they read from memory: SeekHead, Info, Tracks, Cluster, Cues, Tags, Chapters, Attachments
	.long	0x749B4D11, 0x66A94915, 0x6BAE5416, 0x75B6431F, 0x6BBB531C, 0x67C35412, 0x70A74310, 0x69A44119, 0
Lmk_near:                                 ; a cluster's own: Timecode, SimpleBlock, BlockGroup, Position, PrevSize; and Void, CRC-32
	.byte	0xE7, 0xA3, 0xA0, 0xA7, 0xAB, 0xEC, 0xBF, 0
	.p2align 2

; xs_win -> x0 = where the track's file offset 0 is in memory, x1 = how far its bytes go, w2 = 1 if more may come (a stream's) (x19 = track; x9-x11 only).
xs_win:
	ldr	w9, [x19, #TR_SRC]
	cbnz	w9, 1f
	ldr	x0, [x27, #E_MAP]
	ldr	x1, [x27, #E_LEN]
	mov	w2, #0
	ret
1:	ldr	x9, [x19, #TR_ST]         ; a stream's arena, from its position
	ldr	x0, [x9, #ST_AR]
	ldp	x10, x11, [x9, #ST_ARPOS]
	sub	x0, x0, x10
	add	x1, x10, x11
	ldr	w2, [x9, #ST_EOS]
	eor	w2, w2, #1
	ret

; mkv_open(stream) -> w0 = 1 when the mapped file (stream 0), or a stream's first bytes, are Matroska or WebM with a picture or sound CoreMedia decodes: its tracks are read, the first picture and the default sound play (a stream's attached to it); -1: a stream's header is not all in yet.
	.equ MO_INFO,	0                 ; Info, Tracks, Cues: data and end
	.equ MO_TRACKS,	16
	.equ MO_CUES,	32
	.equ MO_SEEKS,	48                ; the SeekHead's data and end
	.equ MO_CTX,	64                ; for mkv_track: the segment and the first cluster (offsets), the Cues and their end, the timestamp scale, the bytes, the stream; w: more bytes may come, a track waits for its first frame
	.equ MO_MORE,	MO_CTX + 56
	.equ MO_WAIT,	MO_CTX + 60
	.equ MO_TMP,	128               ; a Seek's end, and where the SeekHead puts Cues not in yet
	.equ MO_PASS,	144               ; w: the tracks read: 0 pictures and sound, 1 text (there may be no room left for all)
mkv_open:
	FRAME	4, 160
	movi	v0.16b, #0
	stp	q0, q0, [sp]
	stp	q0, q0, [sp, #32]
	stp	q0, q0, [sp, #64]
	stp	q0, q0, [sp, #96]
	stp	q0, q0, [sp, #128]
	str	x0, [sp, #(MO_CTX + 48)]
	cbnz	x0, 1f
	ldr	x19, [x27, #E_MAP]        ; the file
	ldr	x9, [x27, #E_LEN]
	b	2f
1:	ldr	x9, [x0, #ST_ARPOS]       ; a stream: its arena, from its first byte
	cbnz	x9, Lnil4
	ldr	w10, [x0, #ST_EOS]
	sub	w10, w10, #1
	str	w10, [sp, #MO_MORE]
	ldr	x19, [x0, #ST_AR]
	ldr	x9, [x0, #ST_ARN]
2:	add	x20, x19, x9
	str	x19, [sp, #(MO_CTX + 40)]
	mov	x0, x19
	mov	x1, x20
	bl	el_head
	cbz	x0, Lko_short
	MOVL	w9, 0x1A45DFA3            ; EBML
	cmp	w2, w9
	b.ne	Lnil4
	mov	x21, x1
	MOVL	w2, 0x4282                ; its DocType
	bl	el_find
	cbz	x0, Lnil4
	add	x9, x0, #4
	cmp	x9, x1
	b.hi	Lnil4
	ldr	w9, [x0]
	TYPE	w10, 'w','e','b','m'
	TYPE	w11, 'm','a','t','r'
	cmp	w9, w10
	ccmp	w9, w11, #4, ne
	b.ne	Lnil4
	mov	x0, x21
	mov	x1, x20
	bl	el_head
	cbz	x0, Lko_short
	MOVL	w9, 0x18538067            ; the Segment
	cmp	w2, w9
	b.ne	Lnil4
	mov	x21, x0
	mov	x22, x1
	mov	x23, x21
Lko_top:
	mov	x24, x23                  ; the segment's elements up to the first cluster
	mov	x0, x23
	mov	x1, x22
	bl	el_head
	cbnz	x0, 1f
	add	x9, x24, #12              ; cut short by the bytes so far: more first
	ldr	w10, [sp, #MO_MORE]
	cmp	x9, x22
	ccmp	w10, #0, #4, hi
	b.ne	Lko_short
	add	x0, x24, #1               ; garbage: on from the next top-level element
	mov	x1, x22
	bl	el_resync
	mov	x23, x0
	cbnz	x0, Lko_top
	b	Lko_seen
1:	mov	x23, x1
	MOVL	w9, 0x1F43B675            ; a Cluster: the media starts
	cmp	w2, w9
	b.eq	Lko_media
	mov	x9, #MO_INFO
	MOVL	w10, 0x1549A966
	cmp	w2, w10
	b.eq	Lko_keep
	mov	x9, #MO_TRACKS
	MOVL	w10, 0x1654AE6B
	cmp	w2, w10
	b.eq	Lko_keep
	mov	x9, #MO_CUES
	MOVL	w10, 0x1C53BB6B
	cmp	w2, w10
	b.eq	Lko_keep
	mov	x9, #MO_SEEKS
	MOVL	w10, 0x114D9B74
	cmp	w2, w10
	b.ne	Lko_top
Lko_keep:
	add	x10, x0, x3               ; not all in yet: more first
	cmn	x3, #1
	ccmp	x10, x1, #0, ne
	ldr	w11, [sp, #MO_MORE]
	ccmp	w11, #0, #4, hi
	b.ne	Lko_short
	add	x9, sp, x9
	stp	x0, x1, [x9]
	b	Lko_top
Lko_media:
	sub	x9, x24, x19
	str	x9, [sp, #(MO_CTX + 8)]
Lko_seen:
	ldr	x9, [sp, #(MO_CTX + 8)]
	ldr	w10, [sp, #MO_MORE]
	cbnz	x9, 1f
	cbnz	w10, Lko_short            ; no media yet
	b	Lnil4
1:	ldp	x24, x25, [sp, #MO_SEEKS] ; what the SeekHead points at, if not seen yet (Cues usually come last)
Lko_seek:
	cbz	x24, Lko_read
	mov	x0, x24
	mov	x1, x25
	bl	el_head
	cbz	x0, Lko_read
	mov	x24, x1
	MOVL	w9, 0x4DBB                ; a Seek
	cmp	w2, w9
	b.ne	Lko_seek
	mov	x26, x0
	str	x1, [sp, #MO_TMP]
	MOVL	w2, 0x53AC                ; its position
	mov	x3, #-1
	bl	el_num
	adds	x23, x21, x0              ; the element there
	b.cs	Lko_seek
	mov	x0, x26
	ldr	x1, [sp, #MO_TMP]
	MOVL	w2, 0x53AB                ; and its ID
	mov	x3, #0
	bl	el_num
	mov	x9, #MO_INFO
	MOVL	w10, 0x1549A966
	cmp	x0, x10
	b.eq	1f
	mov	x9, #MO_TRACKS
	MOVL	w10, 0x1654AE6B
	cmp	x0, x10
	b.eq	1f
	mov	x9, #MO_CUES
	MOVL	w10, 0x1C53BB6B
	cmp	x0, x10
	b.ne	Lko_seek
1:	add	x26, sp, x9
	ldr	x9, [x26]
	cbnz	x9, Lko_seek              ; seen already
	cmp	x23, x20
	b.lo	2f
	MOVL	w11, 0x1C53BB6B           ; past the bytes so far: a stream fetches its Cues for its first seek
	cmp	w10, w11
	b.ne	Lko_seek
	sub	x9, x23, x19
	str	x9, [sp, #(MO_TMP + 8)]
	b	Lko_seek
2:	mov	w25, w10
	mov	x0, x23
	mov	x1, x22
	bl	el_head
	cbz	x0, Lko_seekn
	cmp	w2, w25
	b.ne	Lko_seekn                 ; not what the index says
	stp	x0, x1, [x26]
Lko_seekn:
	ldr	x25, [sp, #(MO_SEEKS + 8)]
	b	Lko_seek
Lko_read:
	ldp	x0, x1, [sp, #MO_INFO]
	MOVL	w2, 0x2AD7B1              ; the timestamp scale, ns
	MOVL	x3, 1000000
	cbz	x0, 1f
	bl	el_num
	mov	x3, x0
1:	str	x3, [sp, #(MO_CTX + 32)]
	ldp	x0, x1, [sp, #MO_INFO]
	cbz	x0, 2f
	MOVL	w2, 0x4489                ; the duration, in that scale
	bl	el_float
	ldr	d1, [sp, #(MO_CTX + 32)]
	ucvtf	d1, d1
	fmul	d0, d0, d1
	MOVL	x9, 1000000
	ucvtf	d1, x9
	fdiv	d0, d0, d1
	fcvtzs	x9, d0
	str	x9, [x27, #E_DURMS]
2:	mov	w9, #1000
	str	w9, [x27, #E_MTS]
	mov	w9, #1
	str	w9, [x27, #E_ISO]         ; AAC's description is ISO's
	sub	x9, x21, x19
	str	x9, [sp, #MO_CTX]
	ldp	x0, x1, [sp, #MO_CUES]    ; the Cues the tracks read: in the file, or a stream's own copy
	ldr	x26, [sp, #(MO_CTX + 48)]
	cbz	x0, 4f
	cbz	x26, 3f
	sub	x25, x1, x0
	mov	x24, x0
	ldr	x0, [x26, #ST_XIDX]
	mov	x1, x25
	bl	_realloc
	cbz	x0, 4f
	str	x0, [x26, #ST_XIDX]
	str	x25, [x26, #ST_XIDXN]
	str	xzr, [x26, #ST_XCUEP]
	mov	x1, x24
	mov	x2, x25
	bl	_memcpy
	add	x1, x0, x25
3:	stp	x0, x1, [sp, #(MO_CTX + 16)]
	b	5f
4:	cbz	x26, 5f
	ldr	x9, [sp, #(MO_TMP + 8)]
	str	x9, [x26, #ST_XCUEP]
5:	ldp	x23, x24, [sp, #MO_TRACKS]
	cbz	x23, Lnil4
Lko_entry:
	mov	x0, x23
	mov	x1, x24
	bl	el_head
	cbz	x0, Lko_pass
	mov	x23, x1
	cmp	w2, #0xAE                 ; a TrackEntry
	b.ne	Lko_entry
	add	x2, sp, #MO_CTX
	bl	mkv_track
	b	Lko_entry
Lko_pass:
	ldr	w9, [sp, #MO_PASS]        ; then the text tracks
	cbnz	w9, Lko_pick
	mov	w9, #1
	str	w9, [sp, #MO_PASS]
	ldp	x23, x24, [sp, #MO_TRACKS]
	b	Lko_entry
Lko_pick:
	ldr	w9, [sp, #MO_WAIT]
	cbnz	w9, Lko_short             ; a track's first frame is not in yet
	mov	w0, #1
	bl	xs_pick
	cbz	w0, Lnil4
	ldr	x0, [sp, #(MO_CTX + 48)]
	mov	w1, #1
	bl	xs_attach
	mov	w0, #1
	b	Lret4
Lko_short:
	mov	w0, #1                    ; the tracks made so far go, read again with more
	bl	xs_free
	ldr	w0, [sp, #MO_MORE]
	b	Lret4

; xs_pick(kind) -> w0 = 1 with the first picture, and the first default sound (else the first sound), of the Matroska (1) or FLV (2) tracks playing; AVPlayer cannot read them: AirPlay hands nothing off.
xs_pick:
	BADDR	x9, E_TR
	add	x10, x9, #((TRACKS * TR_SIZE) >> 12), lsl #12
	mov	x11, #0
1:	ldr	w12, [x9, #TR_CUR]
	cmp	w12, w0
	b.ne	3f
	ldr	w12, [x9, #TR_KIND]
	cmp	w12, #'v'
	b.ne	2f
	ldr	x13, [x27, #E_VT]
	cbnz	x13, 3f
	str	x9, [x27, #E_VT]
	b	3f
2:	cmp	w12, #'a'
	b.ne	3f
	cmp	x11, #0
	csel	x11, x9, x11, eq
	ldr	w12, [x9, #TR_MDEF]
	ldr	x13, [x27, #E_AT]
	cbz	w12, 3f
	cbnz	x13, 3f
	str	x9, [x27, #E_AT]
3:	add	x9, x9, #TR_SIZE
	cmp	x9, x10
	b.lo	1b
	ldr	x13, [x27, #E_AT]
	cmp	x13, #0
	csel	x13, x11, x13, eq
	str	x13, [x27, #E_AT]
	ldr	x9, [x27, #E_VT]
	orr	x9, x9, x13
	cmp	x9, #0
	cset	w0, ne
	BADDR	x9, B_AIRK
	str	xzr, [x9]
	ret

; xs_attach(stream, kind) — a stream (0: the file, nothing to do) feeds the Matroska (1) or FLV (2) picture and sound that play, their cursors at the target; it has no room for others, which go.
xs_attach:
	FRAME	3
	mov	x20, x0
	cbz	x20, Lret3
	mov	w21, w1
	BADDR	x22, E_TR
	add	x23, x22, #((TRACKS * TR_SIZE) >> 12), lsl #12
1:	mov	x19, x22
	ldr	w9, [x19, #TR_CUR]
	cmp	w9, w21
	b.ne	3f
	ldr	x9, [x27, #E_VT]
	ldr	x10, [x27, #E_AT]
	cmp	x9, x19
	ccmp	x10, x19, #4, ne
	b.ne	2f
	mov	x0, x20
	bl	trk_attach
	mov	x0, x19                   ; a stream's sound format now, as its samples come from here on
	bl	snd_fd
	bl	trk_seek
	b	3f
2:	bl	xs_drop
3:	add	x22, x22, #TR_SIZE
	cmp	x22, x23
	b.lo	1b
	mov	x0, x20
	bl	no_pic                    ; sound alone: no picture waited for
	b	Lret3

; xs_drop — a Matroska or FLV track goes: its format and description freed, its slot cleared (x19 = track).
xs_drop:
	FRAME	0
	ldr	x0, [x19, #TR_FD]
	cbz	x0, 1f
	bl	_CFRelease
1:	ldr	x0, [x19, #TR_FL]
	bl	_free
	mov	x0, x19
	mov	x1, #TR_SIZE
	bl	_bzero
	b	Lret0

; xs_free(kind) — every Matroska (1) or FLV (2) track goes; the tracks read are those up to the last slot still used.
xs_free:
	FRAME	2
	mov	w20, w0
	BADDR	x19, E_TR
	add	x21, x19, #((TRACKS * TR_SIZE) >> 12), lsl #12
1:	ldr	w9, [x19, #TR_CUR]
	cmp	w9, w20
	b.ne	2f
	bl	xs_drop
2:	add	x19, x19, #TR_SIZE
	cmp	x19, x21
	b.lo	1b
	mov	w9, #TRACKS
	BADDR	x11, E_TR
3:	cbz	w9, 4f
	sub	w10, w9, #1
	add	x12, x11, x10, lsl #9
	ldr	w12, [x12, #TR_KIND]
	cbnz	w12, 4f
	mov	w9, w10
	b	3b
4:	str	w9, [x27, #E_NTR]
	b	Lret2

; mkv_codec(id, end) -> x0 = the codec table's entry for that CodecID: {code, the name's length, frames per packet, format}; 0 if this player cannot use it.
mkv_codec:
	FRAME	3
	mov	x19, x0
	sub	x20, x1, x0
	adr	x21, Lmk_codecs
1:	ldrb	w9, [x21]
	cbz	w9, 3f
	ldrb	w22, [x21, #1]
	cmp	x22, x20
	b.hi	2f
	mov	x0, x19
	add	x1, x21, #8
	mov	x2, x22
	bl	_memcmp
	cbnz	w0, 2f
	mov	x0, x21
	b	Lret3
2:	add	x21, x21, #8
	add	x21, x21, x22
	b	1b
3:	mov	x0, #0
	b	Lret3

; Codes: 1-5 pictures (AVC, HEVC, AV1, VP9, ProRes), 16 AAC, 17 sound with no cookie, 18 its CodecPrivate the cookie, 19 FLAC, 20-22 PCM (integer little- and big-endian, float), 32 text, 33 ASS; a name is a CodecID's start.
.macro MKC code, fpp, a, b, c, d, id
	.byte	\code, 1f - 0f
	.short	\fpp
	.byte	\d, \c, \b, \a
0:	.ascii	"\id"
1:
.endm
Lmk_codecs:
	MKC	1, 0, 'a','v','c','1', "V_MPEG4/ISO/AVC"
	MKC	2, 0, 'h','v','c','1', "V_MPEGH/ISO/HEVC"
	MKC	3, 0, 'a','v','0','1', "V_AV1"
	MKC	4, 0, 'v','p','0','9', "V_VP9"
	MKC	5, 0, 0, 0, 0, 0, "V_PRORES"
	MKC	16, 1024, 'a','a','c',' ', "A_AAC"
	MKC	17, 1152, '.','m','p','3', "A_MPEG/L3"
	MKC	17, 1152, '.','m','p','2', "A_MPEG/L2"
	MKC	17, 384, '.','m','p','1', "A_MPEG/L1"
	MKC	17, 1536, 'a','c','-','3', "A_AC3"
	MKC	17, 1536, 'e','c','-','3', "A_EAC3"
	MKC	18, -1, 'o','p','u','s', "A_OPUS"
	MKC	18, 0, 'v','o','r','b', "A_VORBIS"
	MKC	18, 4096, 'a','l','a','c', "A_ALAC"
	MKC	19, 0, 'f','l','a','c', "A_FLAC"
	MKC	20, 1, 'l','p','c','m', "A_PCM/INT/LIT"
	MKC	21, 1, 'l','p','c','m', "A_PCM/INT/BIG"
	MKC	22, 1, 'l','p','c','m', "A_PCM/FLOAT/IEEE"
	MKC	32, 0, 'm','k','t','x', "S_TEXT/UTF8"
	MKC	32, 0, 'w','v','t','x', "S_TEXT/WEBVTT"
	MKC	32, 0, 'w','v','t','b', "D_WEBVTT/SUBTITLES"
	MKC	32, 0, 'w','v','t','b', "D_WEBVTT/CAPTIONS"
	MKC	33, 0, 'm','k','a','s', "S_TEXT/ASS"
	MKC	33, 0, 'm','k','a','s', "S_TEXT/SSA"
	MKC	33, 0, 'm','k','a','s', "S_ASS"
	MKC	33, 0, 'm','k','a','s', "S_SSA"
	.byte	0
	.p2align 2

; mkv_track(entry, end, context) — a TrackEntry becomes the next track if CoreMedia decodes it: its codec, times, language and format (context: mkv_open's MO_CTX).
	.equ MT_ASBD,	16                ; a sound's AudioStreamBasicDescription
	.equ MT_VPCC,	16                ; or a VP9 configuration record
	.equ MT_DIMS,	32                ; a picture's size, then its shown size (w each)
mkv_track:
	FRAME	4, 64
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	Lret4
	BADDR	x10, E_TR
	add	x19, x10, x9, lsl #9      ; the next slot (TR_SIZE 512), taken if this track is
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0xB9                 ; FlagEnabled
	mov	x3, #1
	bl	el_num
	cbz	x0, Lret4
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0x86                 ; CodecID
	bl	el_find
	cbz	x0, Lret4
	bl	mkv_codec
	cbz	x0, Lret4
	mov	x23, x0
	ldrb	w9, [x23]                 ; text in mkv_open's second pass, the rest in its first
	ldr	w10, [x22, #(MO_PASS - MO_CTX)]
	cmp	w9, #32
	cset	w9, hs
	cmp	w9, w10
	b.ne	Lret4
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x6D80                ; ContentEncodings: header stripping only, no compression or encryption
	bl	el_find
	cbz	x0, Lkt_plain
	MOVL	w2, 0x6240
	bl	el_find
	cbz	x0, Lkt_plain
	mov	x24, x0
	mov	x25, x1
	MOVL	w2, 0x5035
	bl	el_find
	cbnz	x0, Lret4
	mov	x0, x24
	mov	x1, x25
	MOVL	w2, 0x5034
	bl	el_find
	cbz	x0, Lkt_plain
	mov	x24, x0
	mov	x25, x1
	MOVL	w2, 0x4254                ; its algorithm: 3, header stripping
	mov	x3, #0
	bl	el_num
	cmp	x0, #3
	b.ne	Lret4
	mov	x0, x24
	mov	x1, x25
	MOVL	w2, 0x4255                ; the bytes cut from every frame: at most 16, kept in the track
	bl	el_find
	cbz	x0, Lkt_plain
	sub	x2, x1, x0
	cmp	x2, #16
	b.hi	Lret4
	str	w2, [x19, #TR_MPREN]
	mov	x1, x0
	add	x0, x19, #TR_MPREB
	bl	_memcpy
Lkt_plain:
	mov	w9, #1
	str	w9, [x19, #TR_CUR]
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0xD7                 ; TrackNumber
	mov	x3, #0
	bl	el_num
	str	w0, [x19, #TR_MNUM]
	str	w0, [x19, #TR_ID]
	ldp	x9, x10, [x22]            ; the segment, the first cluster
	stp	x9, x10, [x19, #TR_MSEG]
	ldp	x9, x10, [x22, #16]       ; the Cues
	stp	x9, x10, [x19, #TR_MCUES]
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0x88                 ; FlagDefault
	mov	x3, #1
	bl	el_num
	str	w0, [x19, #TR_MDEF]
	bl	mkv_lang
	ldrb	w9, [x23]
	cmp	w9, #16
	b.lo	Lkt_video
	cmp	w9, #32
	b.lo	Lkt_sound
	MOVL	w0, 90000                 ; text
	bl	mkv_scale
	ldr	w1, [x23, #4]
	mov	w2, w1
	mov	x0, #0
	mov	x3, #0
	add	x4, x19, #TR_FD
	bl	_CMFormatDescriptionCreate
	cbnz	w0, Lkt_no
	mov	w9, #'s'
	b	Lkt_take
Lkt_video:
	MOVL	w0, 90000
	bl	mkv_scale
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0xE0                 ; Video
	bl	el_find
	cbz	x0, Lkt_no
	mov	x24, x0
	mov	x25, x1
	mov	w2, #0xB0                 ; its size in pixels
	mov	x3, #0
	bl	el_num
	str	w0, [sp, #MT_DIMS]
	mov	x0, x24
	mov	x1, x25
	mov	w2, #0xBA
	mov	x3, #0
	bl	el_num
	str	w0, [sp, #(MT_DIMS + 4)]
	mov	x0, x24
	mov	x1, x25
	MOVL	w2, 0x54B0                ; as shown (its pixel aspect)
	ldr	w3, [sp, #MT_DIMS]
	bl	el_num
	str	w0, [sp, #(MT_DIMS + 8)]
	mov	x0, x24
	mov	x1, x25
	MOVL	w2, 0x54BA
	ldr	w3, [sp, #(MT_DIMS + 4)]
	bl	el_num
	str	w0, [sp, #(MT_DIMS + 12)]
	ldp	w9, w10, [sp, #MT_DIMS]
	cbz	w9, Lkt_no
	cbz	w10, Lkt_no
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x63A2                ; CodecPrivate: the configuration
	bl	el_find
	mov	x26, x0
	sub	x3, x1, x0
	ldrb	w9, [x23]
	ldr	w0, [x23, #4]             ; the sample description's type
	mov	x2, x26
	cmp	w9, #4
	b.lo	Lkt_vbox
	b.eq	Lkt_vp9
	cbz	x26, Lkt_no               ; ProRes: CodecPrivate is its type; no box
	cmp	x3, #4
	b.lo	Lkt_no
	ldr	w0, [x26]
	rev	w0, w0
	mov	w1, #0
	b	Lkt_vfd
Lkt_vbox:
	cbz	x26, Lkt_no
	MOVL	w1, 0x61766343            ; 'avcC', 'hvcC', 'av1C'
	cmp	w9, #2
	MOVL	w10, 0x68766343
	csel	w1, w10, w1, eq
	cmp	w9, #3
	b.ne	Lkt_vfd
	ldr	w10, [x28, #G_AV1]
	cbz	w10, Lkt_no               ; no AV1 decoder here
	ldrb	w10, [x26, #1]
	lsr	w10, w10, #5
	cbnz	w10, Lkt_no               ; the chip decodes AV1's Main profile only
	MOVL	w1, 0x61763143
	b	Lkt_vfd
Lkt_vp9:
	MOVL	w0, 0x76703039            ; 'vp09': its decoder ships with the system, registered once
	CALLF	VTRegisterSupplementalVideoDecoderIfAvailable
	mov	w9, #'v'                  ; its configuration from its first key frame's header
	str	w9, [x19, #TR_KIND]
	ldr	x9, [x22, #48]            ; a stream's: read where it has its bytes
	cbz	x9, 2f
	str	x9, [x19, #TR_ST]
	mov	w10, #1
	str	w10, [x19, #TR_SRC]
2:	mov	x0, #0
	bl	mkv_start
	mov	x24, #0                   ; the frame
	mov	x25, #0
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.lo	3f
	ldr	w9, [x19, #TR_MWAIT]
	cbz	w9, 1f                    ; none: 4:2:0 at 8 bits
	str	w9, [x22, #(MO_WAIT - MO_CTX)] ; not in yet: the header is read again with more
	b	Lkt_no
3:	bl	xs_win
	ldr	x10, [x19, #TR_OFF]
	add	x24, x0, x10
	ldr	w25, [x19, #TR_XSIZE]
1:	mov	x0, x20
	mov	x1, x21
	mov	w2, #0xE0
	bl	el_find
	MOVL	w2, 0x55B0                ; Colour
	cbz	x0, 2f
	bl	el_find
2:	mov	x3, x0
	mov	x4, x1
	mov	x0, x24
	mov	x1, x25
	add	x2, sp, #MT_VPCC
	bl	vp9_cfg
	ldrb	w9, [sp, #(MT_VPCC + 6)]
	ubfx	w9, w9, #1, #3
	cmp	w9, #2
	b.hs	Lkt_no                    ; the chip decodes 4:2:0 VP9 only
	MOVL	w0, 0x76703039
	MOVL	w1, 0x76706343            ; 'vpcC'
	add	x2, sp, #MT_VPCC
	mov	x3, #12
Lkt_vfd:
	ldp	w4, w5, [sp, #MT_DIMS]
	ldp	w6, w7, [sp, #(MT_DIMS + 8)]
	bl	img_fd
	cbnz	w0, Lkt_no
	bl	vid_dims
	mov	w9, #'v'
	b	Lkt_take
Lkt_sound:
	mov	x0, x20
	mov	x1, x21
	mov	w2, #0xE1                 ; Audio
	bl	el_find
	cbz	x0, Lkt_no
	mov	x24, x0
	mov	x25, x1
	movi	v0.16b, #0
	stp	q0, q0, [sp, #MT_ASBD]
	str	d0, [sp, #(MT_ASBD + 32)]
	mov	w2, #0xB5                 ; SamplingFrequency
	bl	el_float
	str	d0, [sp, #MT_ASBD]
	fcvtzu	w26, d0
	cbz	w26, Lkt_no
	mov	w0, w26
	bl	mkv_scale
	mov	x0, x24
	mov	x1, x25
	mov	w2, #0x9F                 ; Channels
	mov	x3, #1
	bl	el_num
	str	w0, [sp, #(MT_ASBD + 28)]
	mov	x0, x24
	mov	x1, x25
	MOVL	w2, 0x6264                ; BitDepth
	mov	x3, #16
	bl	el_num
	str	w0, [sp, #(MT_ASBD + 32)]
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x63A2                ; CodecPrivate
	bl	el_find
	mov	x24, x0
	sub	x25, x1, x0
	cbnz	x0, 1f
	mov	x25, #0
1:	ldr	w9, [x23, #4]
	str	w9, [sp, #(MT_ASBD + 8)]  ; its format
	ldrb	w10, [x23]
	cmp	w10, #20
	b.hs	2f
	str	wzr, [sp, #(MT_ASBD + 32)] ; compressed: no bits per channel
2:	ldrsh	w10, [x23, #2]
	str	w10, [x19, #TR_MFPP]      ; frames per packet: -1 Opus's own, 0 from the timestamps
	cmp	w10, #0
	csel	w10, w10, wzr, gt
	str	w10, [sp, #(MT_ASBD + 20)]
	ldrb	w9, [x23]
	cmp	w9, #16
	b.eq	Lkt_aac
	cmp	w9, #18
	b.lo	Lkt_plainsnd
	b.eq	Lkt_cookie
	cmp	w9, #19
	b.eq	Lkt_flac
	mov	w10, #-2                  ; PCM: a block's every frame is a sample
	str	w10, [x19, #TR_MFPP]
	ldr	w10, [sp, #(MT_ASBD + 28)]
	ldr	w11, [sp, #(MT_ASBD + 32)]
	mul	w10, w10, w11
	lsr	w10, w10, #3              ; bytes per frame
	cbz	w10, Lkt_no
	str	w10, [x19, #TR_FIXED]
	str	w10, [sp, #(MT_ASBD + 16)]
	str	w10, [sp, #(MT_ASBD + 24)]
	mov	w12, #(kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked)
	cmp	w11, #8
	mov	w13, #kAudioFormatFlagIsPacked ; 8 bits: unsigned
	csel	w12, w13, w12, eq
	cmp	w9, #21
	orr	w13, w12, #kAudioFormatFlagIsBigEndian
	csel	w12, w13, w12, eq
	cmp	w9, #22
	mov	w13, #(kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked)
	csel	w12, w13, w12, eq
	str	w12, [sp, #(MT_ASBD + 12)]
	b	Lkt_plainsnd
Lkt_aac:
	cbnz	x24, 2f                   ; an old CodecID without its config: AAC LC's, from the rate and channels
	mov	x9, #0
	GADDR	x10, Lk_rates
3:	ldr	w11, [x10, x9, lsl #2]
	cbz	w11, Lkt_no
	cmp	w11, w26
	b.eq	4f
	add	x9, x9, #1
	b	3b
4:	ldr	w11, [sp, #(MT_ASBD + 28)]
	mov	w12, #(2 << 11)
	orr	w12, w12, w9, lsl #7
	orr	w12, w12, w11, lsl #3
	rev16	w12, w12
	strh	w12, [sp, #(MT_ASBD + 36)]
	add	x24, sp, #(MT_ASBD + 36)
	mov	x25, #2
2:	mov	x0, x24
	mov	x1, x25
	ldr	w2, [sp, #(MT_ASBD + 28)]
	mov	w3, w26
	bl	mp4a_keep
	cbnz	w0, Lkt_no
	b	Lkt_snd
Lkt_cookie:
	ldr	w9, [sp, #(MT_ASBD + 8)]  ; ALAC: CodecPrivate may start with its atom's header; its frames per packet are the config's
	MOVL	w10, 0x616c6163
	cmp	w9, w10
	b.ne	Lkt_opus
	cmp	x25, #36
	b.lo	5f
	ldr	w9, [x24, #4]
	TYPE	w10, 'a','l','a','c'
	cmp	w9, w10
	b.ne	5f
	add	x24, x24, #12
	sub	x25, x25, #12
5:	cmp	x25, #24
	b.lo	Lkt_no
	ldr	w9, [x24]
	rev	w9, w9
	str	w9, [x19, #TR_MFPP]
	str	w9, [sp, #(MT_ASBD + 20)]
	b	Lkt_plainsnd
Lkt_opus:
	MOVL	w10, 0x6f707573
	cmp	w9, w10
	b.ne	Lkt_plainsnd
	mov	w9, #960                  ; Opus: the format's nominal 20 ms
	str	w9, [sp, #(MT_ASBD + 20)]
	b	Lkt_plainsnd
Lkt_flac:
	cmp	x25, #42                  ; "fLaC", STREAMINFO's header, STREAMINFO
	b.lo	Lkt_no
	sub	sp, sp, #64               ; the cookie: a whole dfLa box, STREAMINFO its one block
	add	x0, x24, #8
	add	x1, sp, #(64 + MT_ASBD)
	mov	x2, sp
	bl	flac_fmt
	str	w0, [x19, #TR_MFPP]
	add	x0, sp, #(64 + MT_ASBD)
	mov	x1, sp
	mov	x2, #50
	bl	snd_keep
	add	sp, sp, #64
	cbnz	w0, Lkt_no
	b	Lkt_snd
Lkt_plainsnd:
	add	x0, sp, #MT_ASBD
	mov	x1, x24
	mov	x2, x25
	ldrb	w9, [x23]
	cmp	w9, #18
	b.eq	1f
	mov	x2, #0                    ; no cookie
1:	ldr	w9, [sp, #(MT_ASBD + 8)]
	MOVL	w10, 0x2e6d7033           ; MPEG-2 and 2.5 layer III: 576 frames
	cmp	w9, w10
	b.ne	2f
	mov	w10, #32000
	cmp	w26, w10
	b.hs	2f
	mov	w9, #576
	str	w9, [x19, #TR_MFPP]
	str	w9, [sp, #(MT_ASBD + 20)]
2:	bl	snd_keep
	cbnz	w0, Lkt_no
Lkt_snd:
	mov	w9, #'a'
Lkt_take:
	str	w9, [x19, #TR_KIND]
	mov	w9, #0x7fffffff           ; its frames, until its end shows
	str	w9, [x19, #TR_N]
	ldr	w9, [x27, #E_NTR]
	add	w9, w9, #1
	str	w9, [x27, #E_NTR]
	b	Lret4
Lkt_no:
	bl	xs_drop                   ; the slot stays free
	b	Lret4
	.pushsection __DATA,__data
	.p2align 2
Lk_rates:
	.long	96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350, 0
	.popsection

; mkv_scale(units per second) — the track's time scale; its units per tick, the ticks' rounding, a frame's default duration and the codec's delay in it (x19 = track, x20/x21 = its TrackEntry, x22 = mkv_open's context).
mkv_scale:
	FRAME	0, 16
	str	w0, [x19, #TR_TS]
	ucvtf	d16, w0
	ldr	x9, [x22, #32]
	ucvtf	d17, x9
	fmul	d0, d16, d17
	MOVL	x9, 1000000000
	ucvtf	d18, x9
	fdiv	d0, d0, d18
	str	d0, [x19, #TR_MFAC]
	fcvtps	w9, d0                    ; the rounding: a tick, at least 2 ms (muxers round to the millisecond)
	mov	w10, #500
	udiv	w10, w0, w10
	cmp	w9, w10
	csel	w9, w9, w10, hi
	str	w9, [x19, #TR_MTOL]
	fdiv	d16, d16, d18             ; units per ns
	str	d16, [sp]
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x23E383              ; DefaultDuration
	mov	x3, #0
	bl	el_num
	cmp	x0, #0
	cset	w9, eq                    ; none: estimated from the frames
	str	w9, [x19, #TR_MEST]
	ldr	d16, [sp]
	ucvtf	d0, x0
	fmul	d0, d0, d16
	fcvtns	w9, d0
	str	w9, [x19, #TR_MDDUR]
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x56AA                ; CodecDelay: cut from the start
	mov	x3, #0
	bl	el_num
	ldr	d16, [sp]
	ucvtf	d0, x0
	fmul	d0, d0, d16
	fcvtns	x9, d0
	str	x9, [x19, #TR_SHIFT]
	b	Lret0

; mkv_lang — the track's language: LanguageBCP47's first subtag, else Language, else Matroska's default English; "und" none (x19 = track, x20/x21 = its TrackEntry).
mkv_lang:
	FRAME	0
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x22B59D
	bl	el_find
	cbnz	x0, 1f
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x22B59C
	bl	el_find
	cbnz	x0, 1f
	TYPE	w9, 'e','n','g',0
	b	3f
1:	mov	w9, #0
	mov	w10, #0
2:	cmp	x0, x1
	ccmp	w10, #24, #2, lo
	b.hs	3f
	ldrb	w11, [x0], #1
	cmp	w11, #'-'
	ccmp	w11, #0, #4, ne
	b.eq	3f
	lsl	w11, w11, w10
	orr	w9, w9, w11
	add	w10, w10, #8
	b	2b
3:	TYPE	w10, 'u','n','d',0
	cmp	w9, w10
	csel	w9, wzr, w9, eq
	str	w9, [x19, #TR_LANG]
	b	Lret0

; img_fd(type, box, config, length, width, height, shown width, shown height) -> w0 = 0 with the track's picture format, from an ISO sample description of that type: the config in that box (0: none), a pixel aspect if shown at another shape (x19 = track).
img_fd:
	FRAME	4
	mov	w20, w0
	mov	w21, w1
	mov	x22, x2
	mov	x23, x3
	orr	x24, x4, x5, lsl #32
	orr	x25, x6, x7, lsl #32
	add	x0, x23, #(86 + 8 + 16)
	bl	_malloc
	cbz	x0, 3f
	mov	x26, x0
	mov	x1, #86
	bl	_bzero
	rev	w9, w20
	str	w9, [x26, #4]
	mov	w9, #0x0100               ; big-endian 1: data_reference_index, frame_count
	strh	w9, [x26, #14]
	strh	w9, [x26, #48]
	rev16	w9, w24                   ; width, height
	strh	w9, [x26, #32]
	lsr	x10, x24, #32
	rev16	w10, w10
	strh	w10, [x26, #34]
	mov	w9, #0x4800               ; 72 dpi either way
	stp	w9, w9, [x26, #36]
	mov	w9, #0x1800               ; depth 24
	strh	w9, [x26, #82]
	mov	w9, #0xffff
	strh	w9, [x26, #84]
	mov	x9, #86
	cbz	w21, 1f
	add	x10, x23, #8              ; the config's box
	rev	w10, w10
	rev	w11, w21
	stur	w10, [x26, #86]
	stur	w11, [x26, #90]
	add	x0, x26, #94
	mov	x1, x22
	mov	x2, x23
	bl	_memcpy
	add	x9, x23, #94
1:	mov	w10, w24                  ; shown w by h vs w by shown h: the pixel aspect
	lsr	x11, x24, #32
	mov	w12, w25
	lsr	x13, x25, #32
	mul	x14, x12, x11
	mul	x15, x13, x10
	cmp	x14, x15
	ccmp	x14, #0, #4, ne
	ccmp	x15, #0, #4, ne
	b.eq	2f
	add	x16, x26, x9
	mov	w17, #0x10000000
	str	w17, [x16]
	TYPE	w17, 'p','a','s','p'
	str	w17, [x16, #4]
	rev	w14, w14
	rev	w15, w15
	stp	w14, w15, [x16, #8]
	add	x9, x9, #16
2:	rev	w10, w9
	str	w10, [x26]
	mov	x0, #0
	mov	x1, x26
	mov	x2, x9
	mov	w3, #0
	ldr	x4, [x27, #F_kCMImageDescriptionFlavor_ISOFamily]
	ldr	x4, [x4]
	add	x5, x19, #TR_FD
	CALLF	CMVideoFormatDescriptionCreateFromBigEndianImageDescriptionData
	mov	w20, w0
	mov	x0, x26
	bl	_free
	mov	w0, w20
	b	Lret4
3:	mov	w0, #1
	b	Lret4

; vp9_cfg(frame, size, out, colour, end) — a VP9 configuration record (vpcC's 12 bytes) at out: profile, bit depth, subsampling, range and matrix from a key frame's header (none: 4:2:0 at 8 bits), primaries and transfer from the matrix's standard unless Matroska's Colour gives them.
vp9_cfg:
	FRAME	2
	mov	x19, x2
	mov	x20, x3
	mov	x21, x4
	mov	x9, #0                    ; its first 8 bytes, big-endian
	mov	x10, #0
1:	lsl	x9, x9, #8
	cmp	x10, x1
	b.hs	2f
	ldrb	w11, [x0, x10]
	orr	x9, x9, x11
2:	add	x10, x10, #1
	cmp	x10, #8
	b.lo	1b
	mov	w12, #0                   ; profile
	mov	w13, #8                   ; bit depth
	mov	w14, #1                   ; chroma: 4:2:0
	mov	w15, #0                   ; full range
	mov	w16, #2                   ; matrix: unspecified
	lsr	x10, x9, #62
	cmp	x10, #2                   ; frame_marker
	b.ne	Lv9_put
	ubfx	x10, x9, #61, #1
	ubfx	x11, x9, #60, #1
	orr	w12, w10, w11, lsl #1
	lsl	x9, x9, #4
	cmp	w12, #3
	b.ne	3f
	lsl	x9, x9, #1                ; reserved_zero
3:	tbnz	x9, #63, Lv9_put          ; show_existing_frame
	tbnz	x9, #62, Lv9_put          ; not a key frame
	lsl	x9, x9, #4
	lsr	x10, x9, #40
	MOVL	w11, 0x498342             ; frame_sync_code
	cmp	w10, w11
	b.ne	Lv9_put
	lsl	x9, x9, #24
	cmp	w12, #2
	b.lo	4f
	lsr	x10, x9, #63              ; ten_or_twelve_bit
	mov	w13, #10
	add	w13, w13, w10, lsl #1
	lsl	x9, x9, #1
4:	lsr	x10, x9, #61              ; color_space
	lsl	x9, x9, #3
	adr	x11, Lv9_matrix
	ldrb	w16, [x11, x10]
	cmp	x10, #7
	b.eq	5f                        ; RGB
	lsr	x15, x9, #63              ; color_range
	lsl	x9, x9, #1
	tbz	w12, #0, Lv9_put          ; profiles 0 and 2: 4:2:0
	lsr	x10, x9, #62              ; subsampling x, y
	mov	w14, #3
	cmp	x10, #2
	mov	w11, #2
	csel	w14, w11, w14, eq
	cmp	x10, #3
	mov	w11, #1
	csel	w14, w11, w14, eq
	b	Lv9_put
5:	mov	w15, #1
	tbz	w12, #0, Lv9_put
	mov	w14, #3
Lv9_put:
	mov	w9, #1
	str	w9, [x19]                 ; version 1, no flags
	strb	w12, [x19, #4]
	strb	wzr, [x19, #5]            ; level: not given
	lsl	w13, w13, #4
	orr	w13, w13, w14, lsl #1
	orr	w13, w13, w15
	strb	w13, [x19, #6]
	adr	x9, Lv9_std
	ldrb	w10, [x9, x16]
	strb	w10, [x19, #7]            ; primaries
	add	x9, x9, #10
	ldrb	w10, [x9, x16]
	strb	w10, [x19, #8]            ; transfer
	strb	w16, [x19, #9]            ; matrix
	strh	wzr, [x19, #10]
	cbz	x20, Lret2
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x55BB                ; Primaries
	ldrb	w3, [x19, #7]
	bl	el_num
	strb	w0, [x19, #7]
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x55BA                ; TransferCharacteristics
	ldrb	w3, [x19, #8]
	bl	el_num
	strb	w0, [x19, #8]
	ldrb	w9, [x19, #9]
	cmp	w9, #2
	b.ne	Lret2
	mov	x0, x20
	mov	x1, x21
	MOVL	w2, 0x55B1                ; MatrixCoefficients, when the frame has none
	mov	x3, #2
	bl	el_num
	strb	w0, [x19, #9]
	b	Lret2
Lv9_matrix:
	.byte	2, 6, 1, 6, 7, 9, 2, 0    ; VP9's color spaces: unknown, BT.601, BT.709, SMPTE 170, SMPTE 240, BT.2020, reserved, RGB
Lv9_std:
	.byte	2, 1, 2, 2, 2, 2, 6, 7, 2, 9 ; by matrix: primaries
	.byte	2, 1, 2, 2, 2, 2, 6, 7, 2, 14 ; and transfer
	.p2align 2

; snd_keep(format, cookie, length) -> w0 = 0 with the track's sound description kept for snd_fd: an AudioStreamBasicDescription, the cookie's length, the cookie (x19 = track).
snd_keep:
	FRAME	2
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	add	x0, x22, #44
	bl	_malloc
	cbz	x0, 1f
	str	x0, [x19, #TR_FL]         ; freed with the track
	str	x0, [x19, #TR_STSD]       ; TR_STSDN 0: one of this player's own
	ldp	q0, q1, [x20]
	stp	q0, q1, [x0]
	ldr	d2, [x20, #32]
	str	d2, [x0, #32]
	str	w22, [x0, #40]
	add	x0, x0, #44
	mov	x1, x21
	mov	x2, x22
	bl	_memcpy
	mov	w0, #0
	b	Lret2
1:	mov	w0, #1
	b	Lret2

; flac_fmt(STREAMINFO, ASBD, cookie) -> w0 = frames per packet; the ASBD's source-depth flag and a dfLa cookie are filled (x9-x12 only).
flac_fmt:
	ldrb	w9, [x0, #12]             ; bits per sample - 1, across bytes 12-13
	ldrb	w10, [x0, #13]
	ubfx	w10, w10, #4, #4
	bfi	w10, w9, #4, #1
	add	w10, w10, #1
	mov	w11, #1                   ; the flag: 16, 20, 24 or 32 bits of source
	cmp	w10, #20
	mov	w12, #2
	csel	w11, w12, w11, eq
	cmp	w10, #24
	mov	w12, #3
	csel	w11, w12, w11, eq
	cmp	w10, #32
	mov	w12, #4
	csel	w11, w12, w11, eq
	str	w11, [x1, #12]
	ldp	q0, q1, [x0]              ; the cookie: a dfLa box with STREAMINFO its one block
	ldrh	w9, [x0, #32]
	stp	q0, q1, [x2, #16]
	strh	w9, [x2, #48]
	MOVL	w9, 0x32000000
	TYPE	w10, 'd','f','L','a'
	stp	w9, w10, [x2]
	MOVL	w9, 0x22000080
	stp	wzr, w9, [x2, #8]
	ldrh	w9, [x0]                  ; block sizes, smallest and largest: fixed, every packet's frames
	ldrh	w10, [x0, #2]
	rev16	w9, w9
	rev16	w10, w10
	str	w10, [x1, #20]
	cmp	w9, w10
	csel	w0, w10, wzr, eq
	ret

; mp4a_keep(config, length, channels, rate) -> w0 = 0 with an ISO 'mp4a' sound description of that AAC AudioSpecificConfig kept for snd_fd (x19 = track).
mp4a_keep:
	FRAME	3
	mov	x20, x0
	mov	x21, x1
	mov	w22, w2
	mov	w23, w3
	cmp	x21, #100                 ; one-byte descriptor lengths
	b.hs	2f
	add	x0, x21, #73
	bl	_malloc
	cbz	x0, 2f
	mov	x24, x0
	mov	x1, #73
	bl	_bzero
	add	x9, x21, #73
	rev	w9, w9
	str	w9, [x24]
	TYPE	w9, 'm','p','4','a'
	str	w9, [x24, #4]
	mov	w9, #0x0100
	strh	w9, [x24, #14]            ; data_reference_index 1
	rev16	w9, w22
	strh	w9, [x24, #24]            ; channels
	mov	w9, #0x1000
	strh	w9, [x24, #26]            ; 16 bits
	lsr	w9, w23, #16
	cmp	w9, #0
	csel	w9, w23, wzr, eq          ; the rate, 16.16 (none past 65535: the config's)
	rev16	w9, w9
	strh	w9, [x24, #32]
	add	x9, x21, #37              ; esds
	rev	w9, w9
	str	w9, [x24, #36]
	TYPE	w9, 'e','s','d','s'
	str	w9, [x24, #40]
	mov	w9, #3                    ; ES_Descriptor
	strb	w9, [x24, #48]
	add	w9, w21, #23
	strb	w9, [x24, #49]
	mov	w9, #4                    ; DecoderConfigDescriptor: MPEG-4 audio, an audio stream
	strb	w9, [x24, #53]
	add	w9, w21, #15
	strb	w9, [x24, #54]
	mov	w9, #0x1540
	sturh	w9, [x24, #55]
	mov	w9, #5                    ; DecoderSpecificInfo: the config
	strb	w9, [x24, #68]
	strb	w21, [x24, #69]
	add	x0, x24, #70
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	add	x9, x24, x21
	mov	w10, #0x0106              ; SLConfigDescriptor: predefined 2
	strh	w10, [x9, #70]
	mov	w10, #2
	strb	w10, [x9, #72]
	str	x24, [x19, #TR_FL]
	str	x24, [x19, #TR_STSD]
	add	w9, w21, #73
	str	w9, [x19, #TR_STSDN]
	mov	w0, #0
	b	Lret3
2:	mov	w0, #1
	b	Lret3

; mkv_next -> w0 = 1 with the track's next frame: its laced block's next, else the first of its next block; 0 at the end, where TR_N stops the track (x19 = track).
	.equ MN_TIME,	0                 ; the block's time, ticks
	.equ MN_LACE,	8                 ; w: its lacing, and frames after the first
	.equ MN_MORE,	12
	.equ MN_SIZE,	16                ; the first frame's size, and where the second's is given
	.equ MN_NEXT,	24
	.equ MN_K,	32                ; w: the sizes read
	.equ MN_GO,	36                ; w: more bytes may come (a stream's)
mkv_next:
	FRAME	4, 48
	bl	xs_win
	mov	x20, x0
	add	x21, x0, x1
	str	w2, [sp, #MN_GO]
	ldr	x9, [x19, #TR_XSYNC]
	ubfx	x10, x9, #8, #8
	cbz	x10, Lmn_walk
	sub	x9, x9, #(1 << 8)         ; the block's next frame, right after the last
	str	x9, [x19, #TR_XSYNC]
	sub	w9, w10, #1               ; frames after it
	ldr	x10, [x19, #TR_OFF]
	ldr	w11, [x19, #TR_XSIZE]
	add	x22, x10, x11
	str	x22, [x19, #TR_OFF]
	ldr	x12, [x19, #TR_DTS]
	ldr	w13, [x19, #TR_XDUR]
	add	x12, x12, x13
	str	x12, [x19, #TR_DTS]
	ldr	x12, [x19, #TR_XEND]
	sub	x0, x12, x22              ; the last: the rest of the block
	cbz	w9, Lmn_lsize
	ldr	w13, [x19, #TR_XSYNC]
	ubfx	w13, w13, #1, #2          ; its lacing: 1 Xiph, 2 fixed, 3 EBML
	mov	x0, x11                   ; fixed: as large as the last
	cmp	w13, #2
	b.eq	Lmn_lsize
	ldr	x10, [x19, #TR_XLP]
	add	x0, x20, x10
	add	x1, x20, x12
	cmp	w13, #1
	b.ne	1f
	bl	xiph
	b	2f
1:	bl	vsint                     ; EBML: the difference from the last size
	ldr	w9, [x19, #TR_XSIZE]
	add	x0, x0, x9
2:	sub	x9, x1, x20
	str	x9, [x19, #TR_XLP]
Lmn_lsize:
	ldr	x9, [x19, #TR_XEND]
	sub	x9, x9, x22
	cmp	x0, x9
	csel	x0, x0, x9, ls            ; never past the block
	str	w0, [x19, #TR_XSIZE]
	bl	mkv_fdur
	ldr	w9, [x19, #TR_KIND]       ; a picture's, or a frame with no duration of its own: no start for a seek inside its block
	ldr	w10, [x19, #TR_XDUR]
	ldr	x11, [x19, #TR_XSYNC]
	cmp	w9, #'v'
	ccmp	w10, #0, #4, ne
	b.ne	Lmn_got
	and	x11, x11, #~1
	str	x11, [x19, #TR_XSYNC]
	b	Lmn_got
Lmn_walk:
	ldr	x22, [x19, #TR_XEND]
	tbnz	w9, #3, Lmn_scan
Lmn_el:
	mov	x24, x22                  ; where this element starts
	add	x0, x20, x22
	cmp	x0, x21
	b.hs	Lmn_edge
	ldr	x9, [x19, #TR_XSYNC]      ; at or past its cluster's end: outside it
	cmp	x22, x9, lsr #16
	b.lo	1f
	orr	x9, x9, #0xffffffffffff0000
	str	x9, [x19, #TR_XSYNC]
1:	mov	x1, x21
	bl	el_head
	cbz	x0, Lmn_lost
	sub	x23, x0, x20
	sub	x22, x1, x20
	MOVL	w9, 0x1F43B675            ; a Cluster: into it, its end kept
	cmp	w2, w9
	b.eq	Lmn_cluster
	MOVL	w9, 0x18538067            ; another Segment: into it
	cmp	w2, w9
	b.eq	Lmn_into
	cmn	x3, #1
	b.eq	Lmn_lost                  ; anything else of unknown size, or past its cluster or the file, is damage
	add	x9, x23, x3
	ldr	x10, [x19, #TR_XSYNC]
	cmp	x9, x10, lsr #16
	b.hi	Lmn_lost
	sub	x10, x21, x20
	cmp	x9, x10
	b.hi	Lmn_past                  ; past the bytes so far
	cmp	w2, #0xE7                 ; its time
	b.eq	Lmn_tc
	cmp	w2, #0xA3                 ; a SimpleBlock
	b.eq	Lmn_simple
	cmp	w2, #0xA0                 ; a BlockGroup
	b.eq	Lmn_group
	b	Lmn_el                    ; skipped
Lmn_cluster:
	str	x24, [x19, #TR_XKEY]
	add	x9, x23, x3
	cmn	x3, #1
	csinv	x9, x9, xzr, ne           ; of unknown size: no end
	ldr	x10, [x19, #TR_XSYNC]
	and	x10, x10, #0xffff
	orr	x10, x10, x9, lsl #16
	str	x10, [x19, #TR_XSYNC]
Lmn_into:
	mov	x22, x23
	b	Lmn_el
Lmn_tc:
	bl	el_uint
	str	x0, [x19, #TR_XCTC]
	ldr	w9, [x19, #TR_KIND]
	ldr	w10, [x19, #TR_SRC]
	cmp	w9, #'s'
	ccmp	w10, #0, #0, eq
	b.ne	Lmn_el
	ucvtf	d0, x0
	ldr	d1, [x19, #TR_MFAC]
	fmul	d0, d0, d1
	fcvtzs	x25, d0
	bl	now_ms
	ldr	w9, [x19, #TR_TS]
	mul	x0, x0, x9
	mov	x10, #1000
	sdiv	x0, x0, x10
	ldr	x10, [x19, #TR_TGT]
	cmp	x0, x10
	csel	x0, x0, x10, gt
	add	x0, x0, x9
	cmp	x25, x0
	b.le	Lmn_el
	b	Lmn_park
Lmn_past:
	ldr	w9, [sp, #MN_GO]
	cbz	w9, Lmn_lost              ; the file's end: damage
	mov	w9, w2                    ; a stream's element past the bytes so far waits if it is one Matroska has here, else it is damage
	adr	x10, Lmk_near
1:	ldrb	w11, [x10], #1
	cbz	w11, Lmn_lost
	cmp	w9, w11
	b.eq	Lmn_edge
	b	1b
Lmn_lost:
	add	x9, x20, x24              ; a header cut short by the bytes so far: more first
	add	x9, x9, #12
	cmp	x9, x21
	b.hi	Lmn_edge
	add	x22, x24, #1
Lmn_scan:
	add	x0, x20, x22              ; damage: on from the next top-level element
	mov	x1, x21
	bl	el_resync
	ldr	x9, [x19, #TR_XSYNC]
	cmp	x0, #0
	cset	w10, eq
	bfi	x9, x10, #3, #1
	str	x9, [x19, #TR_XSYNC]
	sub	x22, x0, x20
	sub	x24, x2, x20
	cbnz	x0, Lmn_el
Lmn_edge:
	ldr	w9, [sp, #MN_GO]
	cbz	w9, Lmn_end
Lmn_park:
	str	x24, [x19, #TR_XEND]      ; a stream's: on from this element when more comes
	mov	w9, #1
	str	w9, [x19, #TR_MWAIT]
	ldr	w9, [x19, #TR_I]
	str	w9, [x19, #TR_N]
	mov	w0, #0
	b	Lret4
Lmn_simple:
	mov	w25, #-1                  ; its flags say if it is a key frame
	mov	x26, #0                   ; no duration of its own
	add	x0, x20, x23
	add	x24, x20, x22
	b	Lmn_block
Lmn_group:
	add	x0, x20, x23
	add	x1, x20, x22
	mov	w2, #0xFB                 ; a ReferenceBlock: not a key frame
	bl	el_find
	cmp	x0, #0
	cset	w25, eq
	add	x0, x20, x23
	add	x1, x20, x22
	mov	w2, #0x9B                 ; BlockDuration
	mov	x3, #0
	bl	el_num
	mov	x26, x0
	add	x0, x20, x23
	add	x1, x20, x22
	mov	w2, #0xA1                 ; the Block
	bl	el_find
	cbz	x0, Lmn_el
	mov	x24, x1
Lmn_block:
	mov	x1, x24                   ; x0 = the block, x24 = its end
	bl	vint                      ; its track
	cmp	x1, x24
	b.hi	Lmn_el
	ldr	w9, [x19, #TR_MNUM]
	cmp	x0, x9
	b.ne	Lmn_el                    ; another track's
	add	x9, x1, #3
	cmp	x9, x24
	b.hi	Lmn_el
	ldrb	w10, [x1]
	ldrb	w11, [x1, #1]
	orr	w10, w11, w10, lsl #8
	sxth	x10, w10
	ldr	x11, [x19, #TR_XCTC]
	add	x10, x10, x11
	str	x10, [sp, #MN_TIME]
	ldrb	w11, [x1, #2]             ; flags
	mov	x23, x9                   ; past the header
	cmn	w25, #1
	b.ne	1f
	lsr	w25, w11, #7              ; a SimpleBlock's key frame
1:	ubfx	w12, w11, #1, #2          ; lacing
	stp	w12, wzr, [sp, #MN_LACE]
	str	xzr, [sp, #MN_NEXT]
	sub	x0, x24, x23              ; no lacing: one frame, all of it
	cbz	w12, Lmn_frames
	cmp	x23, x24
	b.hs	Lmn_el
	ldrb	w13, [x23], #1
	str	w13, [sp, #MN_MORE]
	sub	x0, x24, x23
	cmp	w12, #2
	b.ne	2f
	add	w9, w13, #1               ; fixed: all as large
	udiv	x0, x0, x9
	b	Lmn_frames
2:	cbz	w13, Lmn_frames           ; one frame laced
	mov	x0, x23                   ; Xiph or EBML: the first size, where the next is, then past the rest
	mov	x1, x24
	cmp	w12, #1
	b.ne	3f
	bl	xiph
	b	4f
3:	bl	vint
4:	cmp	x1, x24
	b.hi	Lmn_el
	str	x0, [sp, #MN_SIZE]
	sub	x9, x1, x20
	str	x9, [sp, #MN_NEXT]
	mov	x23, x1
	mov	w9, #1
	str	w9, [sp, #MN_K]
5:	ldr	w9, [sp, #MN_K]           ; the sizes after the first; the last frame's is the rest
	ldr	w13, [sp, #MN_MORE]
	cmp	w9, w13
	b.hs	6f
	add	w9, w9, #1
	str	w9, [sp, #MN_K]
	mov	x0, x23
	mov	x1, x24
	ldr	w9, [sp, #MN_LACE]
	cmp	w9, #1
	b.ne	7f
	bl	xiph
	b	8f
7:	bl	vsint
8:	cmp	x1, x24
	b.hi	Lmn_el
	mov	x23, x1
	b	5b
6:	ldr	w0, [sp, #MN_SIZE]
Lmn_frames:
	sub	x9, x24, x23              ; x0 = the first frame's size, x23 = where it is
	cmp	x0, x9
	csel	x0, x0, x9, ls
	sub	x9, x23, x20
	str	x9, [x19, #TR_OFF]
	str	w0, [x19, #TR_XSIZE]
	sub	x9, x24, x20
	str	x9, [x19, #TR_XEND]
	ldp	w12, w13, [sp, #MN_LACE]
	ldr	x9, [sp, #MN_NEXT]
	str	x9, [x19, #TR_XLP]
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'v'
	mov	w10, #1
	csel	w25, w25, w10, eq         ; sound and text: every frame a sync frame
	and	w25, w25, #1
	ldr	x9, [x19, #TR_XSYNC]      ; its cluster's end kept
	and	x9, x9, #0xffffffffffff0000
	orr	x9, x9, x25
	orr	x9, x9, x12, lsl #1
	orr	x9, x9, x13, lsl #8
	str	x9, [x19, #TR_XSYNC]
	ldr	x9, [sp, #MN_TIME]        ; its time and duration, in the track's units
	scvtf	d0, x9
	ldr	d1, [x19, #TR_MFAC]
	fmul	d0, d0, d1
	fcvtns	x10, d0
	bl	xs_est
	str	wzr, [x19, #TR_XCTS]
	ldr	w11, [x19, #TR_MDDUR]     ; the block's duration over its frames, else the default
	cbz	x26, Lmn_dur
	ucvtf	d0, x26
	fmul	d0, d0, d1
	add	w12, w13, #1
	ucvtf	d2, w12
	fdiv	d0, d0, d2
	fcvtns	w11, d0
Lmn_dur:
	ldr	w12, [x19, #TR_MFPP]
	cmp	w12, #0
	csel	w11, w12, w11, gt         ; sound in fixed packets: theirs
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'a'
	b.ne	10f
	ldr	x12, [x19, #TR_DTS]       ; sound: a packet within the ticks' rounding of the last one's end follows it exactly
	ldr	w13, [x19, #TR_XDUR]
	cbz	w13, 10f
	add	x12, x12, x13
	subs	x14, x10, x12
	cneg	x14, x14, mi
	ldr	w15, [x19, #TR_MTOL]
	cmp	x14, x15
	csel	x10, x12, x10, ls
10:	str	x10, [x19, #TR_DTS]
	str	w11, [x19, #TR_XDUR]
	bl	mkv_fdur
Lmn_got:
	bl	xs_learn
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	str	w9, [x19, #TR_I]
	mov	w9, #0x7fffffff           ; and frames after it, as far as it knows
	str	w9, [x19, #TR_N]
	str	wzr, [x19, #TR_MWAIT]
	mov	w0, #1
	b	Lret4
Lmn_end:
	ldr	w9, [x19, #TR_I]
	add	w9, w9, #1
	str	w9, [x19, #TR_I]
	str	w9, [x19, #TR_N]          ; no more
	str	wzr, [x19, #TR_MWAIT]
	mov	w0, #0
	b	Lret4

; mkv_fdur — a frame's own duration: an Opus packet's from its table of contents, PCM's from its size (x19 = track, x20 = the file's bytes).
mkv_fdur:
	ldr	w9, [x19, #TR_MFPP]
	cmn	w9, #2
	b.ne	5f
	ldr	w10, [x19, #TR_XSIZE]
	ldr	w11, [x19, #TR_FIXED]
	udiv	w10, w10, w11
	str	w10, [x19, #TR_XDUR]
	ret
5:	cmn	w9, #1
	b.ne	3f
	ldr	w10, [x19, #TR_XSIZE]
	cbz	w10, 3f
	ldr	x11, [x19, #TR_OFF]
	add	x11, x20, x11
	ldrb	w9, [x11]
	lsr	w12, w9, #3               ; its configuration
	and	w13, w12, #3
	mov	w14, #120                 ; CELT: 2.5, 5, 10, 20 ms
	cmp	w12, #16
	b.hs	1f
	and	w13, w12, #1
	mov	w14, #480                 ; hybrid: 10, 20 ms
	cmp	w12, #12
	b.hs	1f
	and	w13, w12, #3              ; SILK: 10, 20, 40, 60 ms
	cmp	w13, #3
	b.ne	1f
	mov	w14, #2880
	mov	w13, #0
1:	lsl	w14, w14, w13             ; a frame
	ands	w13, w9, #3               ; and how many
	b.eq	2f
	mov	w15, #2
	cmp	w13, #3
	b.ne	4f
	cmp	w10, #2
	b.lo	2f
	ldrb	w15, [x11, #1]
	and	w15, w15, #63
4:	mul	w14, w14, w15
2:	str	w14, [x19, #TR_XDUR]
3:	ret

; xs_guess(ms) -> x0 = where a stream with no index has 10 s before that moment (d0, ms), by its share of the stream's length over the duration, to walk on from; 0 when either is unknown (x19 = track).
xs_guess:
	ldr	x9, [x19, #TR_ST]
	ldr	x13, [x9, #ST_XKEYS]      ; a key frame read before, the last at or before the moment, if within the 10 s
	ldr	w14, [x9, #ST_XKEYN]
	fcvtzs	x15, d0
	mov	x0, #-1
1:	cbz	w14, 2f
	ldp	x16, x17, [x13], #16
	cmp	x17, x15
	b.gt	2f
	mov	x0, x16
	sub	x12, x15, x17
	sub	w14, w14, #1
	b	1b
2:	cmn	x0, #1
	b.eq	3f
	MOVL	w16, 10000
	cmp	x12, x16
	b.ls	1f
3:	ldr	x10, [x9, #ST_XLEN]
	ldr	x11, [x27, #E_DURMS]
	mov	x0, #0
	cbz	x10, 1f
	cbz	x11, 1f
	ldr	x12, [x19, #TR_MCL]
	subs	x10, x10, x12
	b.ls	1f
	MOVL	w9, 10000
	ucvtf	d1, w9
	fsub	d0, d0, d1
	movi	d1, #0
	fmax	d0, d0, d1
	ucvtf	d1, x11
	fdiv	d0, d0, d1
	ucvtf	d1, x10
	fmul	d0, d0, d1
	fcvtzu	x0, d0
	add	x0, x0, x12
1:	ret

; xs_learn — a stream's picture at a key frame past the last one kept: where reading starts for it and its time kept, for seeks within what was read (x19 = track).
	.equ XKEYS_N,	4096              ; 2 h 16 min of key frames 2 s apart
xs_learn:
	ldr	w9, [x19, #TR_KIND]
	ldr	w10, [x19, #TR_SRC]
	ldr	w11, [x19, #TR_XSYNC]
	cmp	w9, #'v'
	ccmp	w10, #0, #4, eq
	b.eq	1f
	tbz	w11, #0, 1f
	FRAME	1
	ldr	x20, [x19, #TR_ST]
	ldr	x0, [x20, #ST_XKEYS]
	cbnz	x0, 2f
	mov	x0, #(XKEYS_N * 16)
	bl	_malloc
	cbz	x0, Lret1
	str	x0, [x20, #ST_XKEYS]
2:	ldr	w9, [x20, #ST_XKEYN]
	ldr	x10, [x19, #TR_XKEY]
	add	x11, x0, x9, lsl #4
	cbz	w9, 3f
	ldur	x12, [x11, #-16]
	cmp	x10, x12
	b.ls	Lret1                     ; read before: kept already
	cmp	w9, #(XKEYS_N >> 12), lsl #12
	b.hs	Lret1                     ; full
3:	ldr	x12, [x19, #TR_DTS]       ; its showing time, ms
	ldrsw	x13, [x19, #TR_XCTS]
	add	x12, x12, x13
	mov	x13, #1000
	mul	x12, x12, x13
	ldr	w13, [x19, #TR_TS]
	sdiv	x12, x12, x13
	stp	x10, x12, [x11]
	add	w9, w9, #1
	str	w9, [x20, #ST_XKEYN]
	b	Lret1
1:	ret

; xs_est — a picture's frame at time x10 (track units): with no duration given, the smallest positive step from the last frame, under a second, is its frames' (x19 = track; x14-x16 only).
xs_est:
	ldr	w14, [x19, #TR_MEST]
	cbz	w14, 1f
	ldr	w14, [x19, #TR_KIND]
	cmp	w14, #'v'
	b.ne	1f
	ldr	x14, [x19, #TR_DTS]
	subs	x14, x10, x14
	b.le	1f
	ldr	w15, [x19, #TR_MDDUR]
	ldr	w16, [x19, #TR_TS]
	cmp	w15, #0
	csel	w15, w16, w15, eq
	cmp	x14, x15
	b.hs	1f
	str	w14, [x19, #TR_MDDUR]
1:	ret

xs_moment:
	mov	x22, x0
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'a'
	b.ne	1f
	ldr	w10, [x19, #TR_TS]
	mov	w11, #5
	udiv	w10, w10, w11
	subs	x22, x22, x10
	csel	x22, x22, xzr, ge
1:	scvtf	d0, x22
	ldr	d1, [x19, #TR_MFAC]
	fdiv	d0, d0, d1
	ret

; mkv_start(moment) — the cursor at the track's first frame in the cluster its index gives for that moment (track units; sound looks 200 ms earlier, for its preroll), a picture's at its first sync frame (x19 = track).
mkv_start:
	FRAME	4, 48
	bl	xs_moment
	fcvtzs	x22, d0                   ; the moment in ticks
	mov	x9, #-1
	str	x9, [sp, #32]
	bl	xs_win
	mov	x20, x0
	add	x21, x0, x1
	ldr	x23, [x19, #TR_MCL]       ; the first cluster, unless the index or the clusters say a later one
	ldp	x24, x25, [x19, #TR_MCUES]
	cbz	x24, Lks_hop
	mov	w26, #1                   ; this track's cue points; if it has none, any track's
Lks_pass:
	ldr	x24, [x19, #TR_MCUES]
Lks_cue:
	mov	x0, x24
	mov	x1, x25
	bl	el_head
	cbz	x0, Lks_passed
	mov	x24, x1
	cmp	w2, #0xBB                 ; a CuePoint
	b.ne	Lks_cue
	stp	x0, x1, [sp]
	mov	w2, #0xB3                 ; its time
	mov	x3, #0
	bl	el_num
	cmp	x0, x22
	b.gt	Lks_passed
	str	x0, [sp, #16]
	ldp	x0, x1, [sp]
	mov	w2, #0xB7                 ; CueTrackPositions
	bl	el_find
	cbz	x0, Lks_cue
	stp	x0, x1, [sp]
	mov	w2, #0xF7                 ; its track
	mov	x3, #0
	bl	el_num
	ldr	w9, [x19, #TR_MNUM]
	cmp	x0, x9
	b.eq	2f
	tbnz	w26, #0, Lks_cue
2:	ldp	x0, x1, [sp]
	mov	w2, #0xF1                 ; its cluster
	mov	x3, #-1
	bl	el_num
	ldr	x9, [x19, #TR_MSEG]
	add	x0, x0, x9
	ldr	w10, [x19, #TR_SRC]       ; the file's: inside it
	sub	x11, x21, x20
	cmp	w10, #0
	ccmp	x0, x11, #0, eq
	b.hs	Lks_cue
	mov	x23, x0
	orr	w26, w26, #4              ; found
	ldr	x9, [sp, #16]
	str	x9, [sp, #24]
	b	Lks_cue
Lks_passed:
	tbz	w26, #0, Lks_line
	tbz	w26, #2, 1f
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'s'
	b.ne	Lks_at
	ldr	x9, [sp, #24]
	stp	x23, x9, [sp, #32]
1:	mov	w26, #2
	b	Lks_pass
Lks_line:
	ldp	x9, x10, [sp, #32]
	mov	x11, #-1
	cmp	x9, x23
	csel	x11, x23, x11, lo
	csel	x23, x9, x23, lo
	str	x11, [sp, #32]
	ucvtf	d0, x10
	ldr	d1, [x19, #TR_MFAC]
	fmul	d0, d0, d1
	fcvtns	x10, d0
	str	x10, [sp, #40]
	b	Lks_at
Lks_hop:
	ldr	w9, [x19, #TR_SRC]
	cbz	w9, Lks_walk
	scvtf	d0, x22                   ; a stream with no index: by the moment's share of its length (the next cluster from there)
	ldr	d1, [x19, #TR_MFAC]
	fmul	d0, d0, d1
	ldr	w9, [x19, #TR_TS]
	ucvtf	d1, w9
	fdiv	d0, d0, d1
	MOVL	w9, 1000
	ucvtf	d1, w9
	fmul	d0, d0, d1                ; in ms
	bl	xs_guess
	cmp	x0, x23
	csel	x23, x0, x23, hi
	b	Lks_at
Lks_walk:
	mov	x24, x23                  ; no index: cluster to cluster while the next starts by then
3:	add	x0, x20, x24
	mov	x1, x21
	bl	el_head
	cbz	x0, Lks_at
	cmn	x3, #1
	b.eq	Lks_at                    ; of unknown size: walked instead
	sub	x9, x1, x20
	str	x9, [sp]
	MOVL	w9, 0x1F43B675
	cmp	w2, w9
	b.ne	4f
	mov	w2, #0xE7
	mov	x3, #0
	bl	el_num
	cmp	x0, x22
	b.gt	Lks_at
	mov	x23, x24
4:	ldr	x24, [sp]
	b	3b
Lks_at:
	str	x23, [x19, #TR_XEND]
	mov	x9, #0x3fffffffffffffff   ; no frame before: no step to the first, no decode time to go on from
	str	x9, [x19, #TR_DTS]
	mov	x9, #0x8000000000000000
	str	x9, [x19, #TR_XDTS]
	mov	x9, #0xffffffffffff0008   ; outside a cluster, no frames left in a block
	str	x9, [x19, #TR_XSYNC]
	str	wzr, [x19, #TR_XDUR]
	str	xzr, [x19, #TR_XCTC]
	mov	w9, #-1
	str	w9, [x19, #TR_I]
	mov	w9, #0x7fffffff
	str	w9, [x19, #TR_N]
5:	bl	xs_step
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'s'
	b.eq	Lks_text
	cbz	w0, Lret4
	cmp	w9, #'v'
	b.ne	Lret4
	ldr	w9, [x19, #TR_XSYNC]
	tbz	w9, #0, 5b                ; a picture starts at a sync frame
	b	Lret4
Lks_text:
	ldp	x9, x10, [sp, #32]
	cmn	x9, #1
	b.eq	Lret4
	cbz	w0, Lks_redo
	ldr	x11, [x19, #TR_DTS]
	cmp	x11, x10
	b.lt	5b
	ldr	x11, [x19, #TR_XEND]
	cmp	x11, x9
	b.hi	Lks_redo
	str	x9, [x19, #TR_XEND]
	b	Lret4
Lks_redo:
	mov	x23, x9
	mov	x9, #-1
	str	x9, [sp, #32]
	b	Lks_at

; xs_start(moment) / xs_step — cur_seek's start and cur_step, for a Matroska or FLV track (x19 = track).
xs_start:
	ldr	w9, [x19, #TR_CUR]
	cmp	w9, #1
	b.eq	mkv_start
	b	flv_start
xs_step:
	ldr	w9, [x19, #TR_CUR]
	cmp	w9, #1
	b.eq	mkv_next
	b	flv_next

; xs_sample(bb, base) -> the cursor's frame as a CMSampleBuffer over bb (holding the file from offset base), the cursor moved on; 0 at the end. Sound from a file takes in the frames after it that follow it in time and last as long, up to 2^ABATCH, copied together if they lie apart (x19 = track).
	.equ XS_SYNC,	0                 ; w: the first frame's sync flag, and whether the bytes were copied
	.equ XS_COPY,	4
	.equ XS_CTS,	8                 ; its composition offset
	.equ XS_LEN,	16                ; the bytes
	.equ XS_SZ,	32                ; the frames' sizes, then their offsets
	.equ XS_OFF,	32 + (8 << ABATCH)
xs_sample:
	FRAME	4, 32 + (16 << ABATCH)
	mov	x25, x0
	mov	x26, x1
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lnil4
	ldr	w9, [x19, #TR_KIND]
	ldr	x10, [x19, #TR_XDTS]
	ldr	w11, [x19, #TR_XSYNC]
	mov	x12, #0x8000000000000000
	cmp	w9, #'v'
	ccmp	x10, x12, #0, eq
	b.ne	1f
	tbnz	w11, #0, 1f
	bl	cur_step
	b	Lnil4
1:	ldr	x20, [x19, #TR_DTS]       ; the first one's time and duration
	ldr	w21, [x19, #TR_XDUR]
	str	w11, [sp, #XS_SYNC]
	ldrsw	x9, [x19, #TR_XCTS]
	str	x9, [sp, #XS_CTS]
	mov	x24, #0                   ; frames
Lxs_add:
	ldr	x10, [x19, #TR_OFF]
	ldr	w11, [x19, #TR_XSIZE]
	ldr	w12, [x19, #TR_MPREN]
	add	x11, x11, x12             ; with what header stripping cut
	add	x9, sp, #XS_SZ
	str	x11, [x9, x24, lsl #3]
	add	x9, sp, #XS_OFF
	str	x10, [x9, x24, lsl #3]
	add	x24, x24, #1
	bl	cur_step
	ldr	w9, [x19, #TR_KIND]
	ldr	w10, [x19, #TR_SRC]
	cmp	w9, #'a'
	ccmp	w10, #0, #0, eq
	b.ne	Lxs_make                  ; a stream's sound, one frame a buffer: its fetching counts what is queued
	tbnz	x24, #ABATCH, Lxs_make
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	Lxs_make
	ldr	w9, [x19, #TR_XDUR]
	cmp	w9, w21
	b.ne	Lxs_make
	ldr	x10, [x19, #TR_DTS]
	madd	x11, x24, x21, x20        ; where it would follow
	cmp	x10, x11
	b.eq	Lxs_add
Lxs_make:
	ldr	w9, [x19, #TR_MPREN]      ; in place if they lie together and whole, else copied
	add	x10, sp, #XS_OFF
	add	x11, sp, #XS_SZ
	ldr	x12, [x10]
	mov	x13, x12
	mov	x14, #0
	mov	x15, #0
1:	ldr	x16, [x10, x15, lsl #3]
	ldr	x17, [x11, x15, lsl #3]
	cmp	x16, x13
	csinc	w9, w9, w9, eq
	add	x13, x16, x17
	add	x14, x14, x17
	add	x15, x15, #1
	cmp	x15, x24
	b.lo	1b
	str	x14, [sp, #XS_LEN]
	str	w9, [sp, #XS_COPY]
	mov	x0, x25
	sub	x1, x12, x26
	cbz	w9, Lxs_times
	mov	x0, x24
	add	x1, sp, #XS_SZ
	add	x2, sp, #XS_OFF
	mov	x3, x14
	bl	xs_copy
	cbz	x0, Lnil4
	mov	x25, x0
	mov	x1, #0
Lxs_times:
	ldr	x2, [sp, #XS_LEN]
	ldr	x9, [x19, #TR_SHIFT]
	sub	x3, x20, x9               ; decode time
	ldr	x10, [sp, #XS_CTS]
	add	x4, x3, x10               ; presentation time
	ldr	w11, [x19, #TR_CUR]
	ldr	w12, [x19, #TR_KIND]
	cmp	w12, #'v'
	b.ne	2f
	cmp	w11, #1
	b.ne	1f
	ldr	x9, [x19, #TR_XDTS]       ; a Matroska picture has none: made up, the last one's plus a frame, held to its showing, never falling
	ldr	w10, [x19, #TR_MDDUR]
	mov	x11, #0x8000000000000000
	cmp	x9, x11
	sub	x3, x4, x10, lsl #1       ; the first since the seek: two frames before it shows
	b.eq	1f
	add	x3, x9, x10
	cmp	x3, x4
	csel	x3, x3, x4, lt
	cmp	x3, x9
	csel	x3, x3, x9, gt
1:	str	x3, [x19, #TR_XDTS]
2:	mov	x5, x21
	ldr	w9, [x19, #TR_KIND]       ; sound with no durations of its own: the time to the next block, shared
	ldr	w10, [x19, #TR_I]
	ldr	w11, [x19, #TR_N]
	cmp	w9, #'a'
	ccmp	x21, #0, #0, eq
	ccmp	w10, w11, #2, eq
	b.hs	4f
	ldr	x9, [x19, #TR_DTS]
	subs	x9, x9, x20
	b.le	4f
	udiv	x5, x9, x24
4:	ldr	w6, [sp, #XS_SYNC]
	and	w6, w6, #1
	mov	w7, w24
	add	x8, sp, #XS_SZ
	ldr	w9, [x19, #TR_MFPP]
	cmn	w9, #2
	b.ne	3f
	ldr	w9, [x19, #TR_FIXED]      ; PCM: every frame a sample
	udiv	x7, x2, x9
	mov	x8, #0
	mov	x5, #1
3:	bl	Lmk_samples
	ldr	w9, [sp, #XS_COPY]
	cbz	w9, Lret4
	mov	x20, x0
	mov	x0, x25                   ; the copy's buffer: the sample keeps it
	bl	_CFRelease
	mov	x0, x20
	b	Lret4

; xs_copy(frames, sizes, offsets, length) -> x0 = a CMBlockBuffer of those frames copied one after another, each with the bytes header stripping cut put back first; 0 without memory (x19 = track).
xs_copy:
	FRAME	4, 16
	mov	x20, x0
	mov	x21, x1
	mov	x22, x2
	mov	x23, x3
	mov	x0, x23
	bl	_malloc
	cbz	x0, Lret4
	mov	x24, x0
	mov	x25, x0                   ; where the next one goes
	bl	xs_win
	mov	x26, x0
1:	cbz	x20, 3f
	ldr	w2, [x19, #TR_MPREN]
	cbz	w2, 2f
	add	x1, x19, #TR_MPREB
	mov	x0, x25
	bl	_memcpy
	ldr	w9, [x19, #TR_MPREN]
	add	x25, x25, x9
2:	ldr	x9, [x22], #8
	add	x1, x26, x9
	ldr	x2, [x21], #8
	ldr	w9, [x19, #TR_MPREN]
	sub	x2, x2, x9
	mov	x0, x25
	add	x25, x25, x2
	bl	_memcpy
	sub	x20, x20, #1
	b	1b
3:	add	x9, sp, #8
	str	x9, [sp]                  ; the 9th argument
	str	xzr, [sp, #8]
	mov	x0, #0
	mov	x1, x24
	mov	x2, x23
	mov	x3, #0                    ; the default allocator frees it
	mov	x4, #0
	mov	x5, #0
	mov	x6, x23
	mov	w7, #0
	bl	_CMBlockBufferCreateWithMemoryBlock
	cbnz	w0, 4f
	ldr	x0, [sp, #8]
	b	Lret4
4:	mov	x0, x24
	bl	_free
	mov	x0, #0
	b	Lret4

; ---- FLV: tags read in place from the mapped file, like Matroska's blocks ----

; flv_open(stream) -> w0 = 1 when the mapped file (stream 0), or a stream's first bytes, are FLV with a picture or sound CoreMedia decodes (AVC and HEVC, legacy or enhanced, AV1, VP9; AAC, MP3, Opus, FLAC, PCM, G.711): its tracks are read and play (a stream's attached to it); -1: a stream's first tags are not in yet.
	.equ FO_META,	0                 ; onMetaData's value, and its tag's end
	.equ FO_VCFG,	16                ; the picture's sequence start: config, end
	.equ FO_ACFG,	32                ; the sound's, if it has one
	.equ FO_ATAG,	48                ; the first sound tag's data and end
	.equ FO_KEYS,	64                ; offsets of onMetaData's keyframes: positions, then times (AMF strict arrays); 0 none
	.equ FO_FIRST,	80                ; the first tag's offset
	.equ FO_VCC,	88                ; w: the picture's codec ('avc1', 'hvc1', 'av01', 'vp09')
	.equ FO_DIMS,	92                ; w: its size from onMetaData
	.equ FO_TMP,	104               ; scratch, 48 bytes
	.equ FO_STREAM,	152               ; the stream, 0 the file; w: more bytes may come
	.equ FO_MORE,	160
flv_open:
	FRAME	4, 176
	movi	v0.16b, #0
	stp	q0, q0, [sp]
	stp	q0, q0, [sp, #32]
	stp	q0, q0, [sp, #64]
	stp	q0, q0, [sp, #96]
	stp	q0, q0, [sp, #128]
	stp	q0, q0, [sp, #144]
	str	x0, [sp, #FO_STREAM]
	cbnz	x0, 1f
	ldr	x19, [x27, #E_MAP]        ; the file
	ldr	x9, [x27, #E_LEN]
	b	2f
1:	ldr	x9, [x0, #ST_ARPOS]       ; a stream: its arena, from its first byte
	cbnz	x9, Lnil4
	ldr	w10, [x0, #ST_EOS]
	eor	w10, w10, #1
	str	w10, [sp, #FO_MORE]
	ldr	x19, [x0, #ST_AR]
	ldr	x9, [x0, #ST_ARN]
2:	add	x20, x19, x9
	cmp	x9, #13
	b.lo	Lfo_short
	ldr	w9, [x19]
	TYPE	w10, 'F','L','V',1
	cmp	w9, w10
	b.ne	Lnil4
	ldr	w9, [x19, #5]
	rev	w9, w9                    ; the header's size, then PreviousTagSize0: the first tag
	add	x21, x19, x9
	add	x21, x21, #4
	cmp	x21, x20
	b.hs	Lfo_short
	sub	x9, x21, x19
	str	x9, [sp, #FO_FIRST]
	mov	x22, x21
	mov	w23, #256                 ; the first tags give the formats
Lfo_tag:
	subs	w23, w23, #1
	b.lo	Lfo_seen
	add	x9, x22, #11
	cmp	x9, x20
	b.hi	Lfo_seen
	ldrb	w24, [x22]
	and	w24, w24, #31             ; its type
	ldr	w9, [x22]
	rev	w9, w9
	and	x9, x9, #0xffffff         ; its size
	add	x25, x22, #11             ; its data
	add	x26, x25, x9
	cmp	x26, x20
	b.hi	Lfo_seen
	add	x22, x26, #4              ; the next tag
	cmp	w24, #18
	b.ne	Lfo_vtag
	ldr	x9, [sp, #FO_META]        ; script data: onMetaData's value
	cbnz	x9, Lfo_tag
	add	x9, x25, #13
	cmp	x9, x26
	b.hi	Lfo_tag
	ldrb	w9, [x25]
	ldrh	w10, [x25, #1]
	mov	w11, #0x0a00
	cmp	w9, #2                    ; a string, 10 long
	ccmp	w10, w11, #0, eq
	b.ne	Lfo_tag
	add	x0, x25, #3
	adr	x1, Ls_onmeta
	mov	x2, #10
	bl	_memcmp
	cbnz	w0, Lfo_tag
	add	x9, x25, #13
	stp	x9, x26, [sp, #FO_META]
	b	Lfo_tag
Lfo_vtag:
	cmp	w24, #9
	b.ne	Lfo_atag
	ldr	x9, [sp, #FO_VCFG]        ; a picture: its sequence start
	cbnz	x9, Lfo_tag
	add	x9, x25, #5
	cmp	x9, x26
	b.hi	Lfo_tag
	ldrb	w10, [x25]
	tbnz	w10, #7, 2f
	ldrb	w12, [x25, #1]            ; legacy: AVC (7) or HEVC (12), packet type 0
	cbnz	w12, Lfo_tag
	and	w11, w10, #15
	MOVL	w13, 0x61766331
	cmp	w11, #7
	b.eq	1f
	MOVL	w13, 0x68766331
	cmp	w11, #12
	b.ne	Lfo_tag
1:	str	w13, [sp, #FO_VCC]
	stp	x9, x26, [sp, #FO_VCFG]
	b	Lfo_tag
2:	tst	w10, #15                  ; enhanced: SequenceStart, after its FourCC
	b.ne	Lfo_tag
	ldr	w13, [x25, #1]
	rev	w13, w13
	b	1b
Lfo_atag:
	cmp	w24, #8
	b.ne	Lfo_tag
	ldr	x9, [sp, #FO_ATAG]        ; sound: its first tag
	cbnz	x9, 3f
	stp	x25, x26, [sp, #FO_ATAG]
3:	ldr	x9, [sp, #FO_ACFG]        ; and its sequence start: AAC's packet type 0, an enhanced one's SequenceStart
	cbnz	x9, Lfo_tag
	add	x9, x25, #2
	cmp	x9, x26
	b.hi	Lfo_tag
	ldrb	w10, [x25]
	lsr	w11, w10, #4
	cmp	w11, #10
	b.ne	4f
	ldrb	w12, [x25, #1]
	cbnz	w12, Lfo_tag
	stp	x9, x26, [sp, #FO_ACFG]
	b	Lfo_tag
4:	cmp	w11, #9
	b.ne	Lfo_tag
	tst	w10, #15
	b.ne	Lfo_tag
	add	x9, x25, #5
	cmp	x9, x26
	b.hi	Lfo_tag
	stp	x9, x26, [sp, #FO_ACFG]
	b	Lfo_tag
Lfo_seen:
	ldr	w9, [sp, #FO_MORE]        ; a stream: the formats its header promises, in its first 4 MiB
	cbz	w9, 1f
	sub	x9, x20, x19
	cmp	x9, #0x400000
	b.hs	1f
	ldrb	w9, [x19, #4]
	ldr	x10, [sp, #FO_VCFG]
	ldr	x11, [sp, #FO_ATAG]
	tbz	w9, #0, 2f
	cbz	x10, Lfo_short
2:	tbz	w9, #2, 1f
	cbz	x11, Lfo_short
1:	mov	w9, #1000                 ; times in ms
	str	w9, [x27, #E_MTS]
	mov	w9, #1
	str	w9, [x27, #E_ISO]
	ldp	x24, x25, [sp, #FO_META]  ; onMetaData: an ECMA array or an object of properties
	cbz	x24, Lfo_dur
	ldrb	w9, [x24], #1
	cmp	w9, #8
	b.ne	1f
	add	x24, x24, #4              ; past its count
	b	2f
1:	cmp	w9, #3
	b.ne	Lfo_dur
2:	mov	x0, x24
	mov	x1, x25
	adr	x2, Ls_duration
	mov	x3, #8
	bl	amf_prop
	bl	amf_num
	MOVL	w9, 1000
	ucvtf	d1, w9
	fmul	d0, d0, d1
	fcvtzs	x9, d0
	str	x9, [x27, #E_DURMS]
	mov	x0, x24
	mov	x1, x25
	adr	x2, Ls_width
	mov	x3, #5
	bl	amf_prop
	bl	amf_num
	fcvtzu	w9, d0
	str	w9, [sp, #FO_DIMS]
	mov	x0, x24
	mov	x1, x25
	adr	x2, Ls_height
	mov	x3, #6
	bl	amf_prop
	bl	amf_num
	fcvtzu	w9, d0
	str	w9, [sp, #(FO_DIMS + 4)]
	mov	x0, x24                   ; keyframes: {filepositions, times}, arrays as long
	mov	x1, x25
	adr	x2, Ls_keyframes
	mov	x3, #9
	bl	amf_prop
	cbz	x0, Lfo_dur
	ldrb	w9, [x0]
	cmp	w9, #3
	b.ne	Lfo_dur
	add	x24, x0, #1               ; its properties
	mov	x0, x24
	mov	x1, x25
	adr	x2, Ls_filepos
	mov	x3, #13
	bl	amf_prop
	mov	x26, x0
	mov	x0, x24
	mov	x1, x25
	adr	x2, Ls_times
	mov	x3, #5
	bl	amf_prop
	cbz	x0, Lfo_dur
	cbz	x26, Lfo_dur
	ldrb	w9, [x0]
	ldrb	w10, [x26]
	cmp	w9, #10
	ccmp	w10, #10, #0, eq
	b.ne	Lfo_dur
	ldur	w9, [x0, #1]
	ldur	w10, [x26, #1]
	rev	w9, w9
	rev	w10, w10
	cmp	w9, w10
	ccmp	w9, #0, #4, eq
	b.eq	Lfo_dur
	mov	w11, #9                   ; every entry a number (9 bytes) inside the tag
	cmp	x0, x26
	csel	x12, x0, x26, hi
	umaddl	x11, w9, w11, x12
	add	x11, x11, #5
	cmp	x11, x25
	b.hi	Lfo_dur
	stp	x26, x0, [sp, #FO_KEYS]
	ldr	x22, [sp, #FO_STREAM]     ; a stream keeps its own copy of onMetaData for them
	cbz	x22, Lfo_dur
	ldp	x23, x24, [sp, #FO_META]
	sub	x24, x24, x23
	mov	x0, x24
	bl	_malloc
	cbz	x0, 3f
	str	x0, [x22, #ST_XIDX]
	str	x24, [x22, #ST_XIDXN]
	mov	x1, x23
	mov	x2, x24
	bl	_memcpy
	ldp	x9, x10, [sp, #FO_KEYS]
	sub	x9, x9, x23
	sub	x10, x10, x23
	add	x9, x0, x9
	add	x10, x0, x10
	stp	x9, x10, [sp, #FO_KEYS]
	b	Lfo_dur
3:	stp	xzr, xzr, [sp, #FO_KEYS]
Lfo_dur:
	ldr	x9, [x27, #E_DURMS]       ; none given: the file's last tag's time, from the size before its end
	ldr	x10, [sp, #FO_STREAM]
	orr	x9, x9, x10
	cbnz	x9, 3f
	ldr	w9, [x20, #-4]
	rev	w9, w9
	sub	x10, x20, #4
	sub	x10, x10, x9
	cmp	x10, x21
	b.lo	3f
	add	x11, x10, #8
	cmp	x11, x20
	b.hi	3f
	ldr	w11, [x10, #4]            ; its timestamp: 24 bits, then the 8 above them
	rev	w11, w11
	lsr	w12, w11, #8
	orr	w12, w12, w11, lsl #24
	str	x12, [x27, #E_DURMS]
3:	ldr	w9, [sp, #FO_VCC]
	cbz	w9, 4f
	mov	x0, sp
	bl	flv_video
4:	ldr	x9, [sp, #FO_ATAG]
	cbz	x9, 5f
	mov	x0, sp
	bl	flv_sound
5:	mov	w0, #2                    ; the picture and the sound
	bl	xs_pick
	cbz	w0, Lnil4
	ldr	x0, [sp, #FO_STREAM]
	mov	w1, #2
	bl	xs_attach
	mov	w0, #1
	b	Lret4
Lfo_short:
	ldr	w9, [sp, #FO_MORE]
	cbz	w9, Lnil4
	mov	w0, #-1
	b	Lret4
Ls_onmeta:	.ascii	"onMetaData"
Ls_duration:	.ascii	"duration"
Ls_width:	.ascii	"width"
Ls_height:	.ascii	"height"
Ls_keyframes:	.ascii	"keyframes"
Ls_filepos:	.ascii	"filepositions"
Ls_times:	.ascii	"times"
	.p2align 2

; amf_skip(p, end, depth) -> x0 = past the AMF0 value at p, 0 if it does not fit or nests deeper than 8.
amf_skip:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	w21, w2
	cmp	w21, #8
	b.hs	Las_no
	add	x9, x19, #1
	cmp	x9, x20
	b.hi	Las_no
	ldrb	w9, [x19]
	mov	x0, #9                    ; number
	cbz	w9, Las_fixed
	mov	x0, #2                    ; boolean
	cmp	w9, #1
	b.eq	Las_fixed
	mov	x0, #1                    ; null, undefined
	cmp	w9, #5
	ccmp	w9, #6, #4, ne
	b.eq	Las_fixed
	mov	x0, #3                    ; reference
	cmp	w9, #7
	b.eq	Las_fixed
	mov	x0, #11                   ; date
	cmp	w9, #11
	b.eq	Las_fixed
	cmp	w9, #2                    ; string: 16-bit length
	b.ne	1f
	add	x10, x19, #3
	cmp	x10, x20
	b.hi	Las_no
	ldrh	w10, [x19, #1]
	rev16	w10, w10
	add	x0, x10, #3
	b	Las_fixed
1:	cmp	w9, #12                   ; long string: 32-bit length
	b.ne	2f
	add	x10, x19, #5
	cmp	x10, x20
	b.hi	Las_no
	ldur	w10, [x19, #1]
	rev	w10, w10
	add	x0, x10, #5
	b	Las_fixed
2:	cmp	w9, #10                   ; strict array: a count of values
	b.ne	4f
	add	x10, x19, #5
	cmp	x10, x20
	b.hi	Las_no
	ldur	w22, [x19, #1]
	rev	w22, w22
	mov	x0, x10
3:	cbz	w22, Lret2
	mov	x1, x20
	add	w2, w21, #1
	bl	amf_skip
	cbz	x0, Lret2
	sub	w22, w22, #1
	b	3b
4:	add	x0, x19, #1               ; object (3) and ECMA array (8, a count first): properties to their end
	cmp	w9, #3
	b.eq	5f
	cmp	w9, #8
	b.ne	Las_no
	add	x0, x19, #5
5:	add	x9, x0, #3
	cmp	x9, x20
	b.hi	Las_no
	ldrh	w10, [x0]
	rev16	w10, w10
	ldrb	w11, [x0, #2]
	cmp	w10, #0
	ccmp	w11, #9, #0, eq
	b.eq	6f                        ; an empty name and 9: the end
	add	x0, x0, #2
	add	x0, x0, x10
	cmp	x0, x20
	b.hi	Las_no
	mov	x1, x20
	add	w2, w21, #1
	bl	amf_skip
	cbz	x0, Lret2
	b	5b
6:	add	x0, x0, #3
	b	Lret2
Las_fixed:
	add	x0, x19, x0
	cmp	x0, x20
	b.ls	Lret2
Las_no:
	mov	x0, #0
	b	Lret2

; amf_prop(properties, end, name, length) -> x0 = the value of the property with that name, 0 if none.
amf_prop:
	FRAME	2
	mov	x19, x0
	mov	x20, x1
	mov	x21, x2
	mov	x22, x3
1:	add	x9, x19, #3
	cmp	x9, x20
	b.hi	3f
	ldrh	w9, [x19]
	rev16	w9, w9                    ; its name's length
	cbz	w9, 3f
	add	x10, x19, #2
	add	x11, x10, x9
	cmp	x11, x20
	b.hs	3f
	cmp	x9, x22
	b.ne	2f
	mov	x0, x10
	mov	x1, x21
	mov	x2, x22
	bl	_memcmp
	add	x10, x19, #2
	add	x11, x10, x22
	cbnz	w0, 2f
	mov	x0, x11
	b	Lret2
2:	mov	x0, x11                   ; another: past its value
	mov	x1, x20
	mov	w2, #0
	bl	amf_skip
	mov	x19, x0
	cbnz	x0, 1b
3:	mov	x0, #0
	b	Lret2

; amf_num(value) -> d0 = an AMF0 number's value (0 for anything else or none).
amf_num:
	movi	d0, #0
	cbz	x0, 1f
	ldrb	w9, [x0]
	cbnz	w9, 1f
	ldur	x9, [x0, #1]
	rev	x9, x9
	fmov	d0, x9
1:	ret

; flv_track(kind, units per second, context) -> x0 = the next free track as an FLV one of that kind, its first tag and index from flv_open's context; 0 if none is free.
flv_track:
	ldr	w9, [x27, #E_NTR]
	cmp	w9, #TRACKS
	b.hs	1f
	BADDR	x10, E_TR
	add	x3, x10, x9, lsl #9
	mov	w9, #2
	str	w9, [x3, #TR_CUR]
	mov	w9, #9                    ; its tags' type: 9 pictures, 8 sound
	mov	w10, #8
	cmp	w0, #'v'
	csel	w9, w9, w10, eq
	str	w9, [x3, #TR_MNUM]
	stp	w0, w1, [x3, #TR_KIND]
	ucvtf	d0, w1
	mov	w9, #1000
	ucvtf	d1, w9
	fdiv	d0, d0, d1
	str	d0, [x3, #TR_MFAC]        ; units per ms
	fcvtps	w9, d0
	lsl	w9, w9, #1                ; the timestamps' rounding: 2 ms
	str	w9, [x3, #TR_MTOL]
	ldr	x9, [x2, #FO_FIRST]
	str	x9, [x3, #TR_MCL]
	ldp	x9, x10, [x2, #FO_KEYS]
	stp	x9, x10, [x3, #TR_MCUES]
	mov	w9, #0x7fffffff
	str	w9, [x3, #TR_N]
	mov	w9, #1                    ; frames of no duration of their own
	str	w9, [x3, #TR_MEST]
	mov	x0, x3
	ret
1:	mov	x0, #0
	ret

; flv_take(made) — the track joins (w0 = 0), or its slot is freed (x19 = track).
flv_take:
	cbnz	w0, xs_drop
	ldr	w9, [x27, #E_NTR]
	add	w9, w9, #1
	str	w9, [x27, #E_NTR]
	ret

; flv_video(context) — the picture's track, its format from its sequence start: AVC's and HEVC's from their parameter sets, AV1's and VP9's at onMetaData's size.
flv_video:
	FRAME	2, 0, 1
	mov	x20, x0
	mov	w0, #'v'
	mov	w1, #1000
	mov	x2, x20
	bl	flv_track
	cbz	x0, Lret2
	mov	x19, x0
	ldp	x21, x22, [x20, #FO_VCFG]
	sub	x1, x22, x21
	mov	x0, x21
	ldr	w9, [x20, #FO_VCC]
	MOVL	w10, 0x61766331           ; 'avc1'
	mov	w2, #0
	cmp	w9, w10
	b.eq	1f
	MOVL	w10, 0x68766331           ; 'hvc1'
	mov	w2, #1
	cmp	w9, w10
	b.ne	2f
1:	bl	ps_fd
	b	Lfv_take
2:	ldp	w4, w5, [x20, #FO_DIMS]   ; AV1, VP9: at the size onMetaData gives
	cbz	w4, Lfv_no
	cbz	w5, Lfv_no
	mov	w6, w4
	mov	w7, w5
	MOVL	w10, 0x61763031           ; 'av01'
	cmp	w9, w10
	b.ne	3f
	ldr	w10, [x28, #G_AV1]
	cbz	w10, Lfv_no
	cmp	x1, #4
	b.lo	Lfv_no
	ldrb	w10, [x21, #1]
	lsr	w10, w10, #5
	cbnz	w10, Lfv_no               ; Main profile only
	mov	x3, x1
	mov	x2, x21
	mov	w0, w9
	MOVL	w1, 0x61763143            ; 'av1C'
	bl	img_fd
	b	Lfv_take
3:	MOVL	w10, 0x76703039           ; 'vp09': its record in vpcC's version 1 box
	cmp	w9, w10
	b.ne	Lfv_no
	cmp	x1, #8
	b.lo	Lfv_no
	ldrb	w10, [x21, #2]
	ubfx	w10, w10, #1, #3
	cmp	w10, #2
	b.hs	Lfv_no                    ; 4:2:0 only
	MOVL	w0, 0x76703039
	CALLF	VTRegisterSupplementalVideoDecoderIfAvailable
	ldp	w4, w5, [x20, #FO_DIMS]
	mov	w6, w4
	mov	w7, w5
	mov	w9, #1
	str	w9, [x20, #FO_TMP]
	ldr	x9, [x21]
	stur	x9, [x20, #(FO_TMP + 4)]
	mov	w9, #0
	sturh	w9, [x20, #(FO_TMP + 10)]  ; no codec initialization data
	MOVL	w0, 0x76703039
	MOVL	w1, 0x76706343            ; 'vpcC'
	add	x2, x20, #FO_TMP
	mov	x3, #12
	bl	img_fd
	b	Lfv_take
Lfv_no:
	mov	w0, #1
Lfv_take:
	bl	flv_take
	b	Lret2

; ps_fd(config, length, hevc) -> w0 = 0 with the track's picture format from an avcC or hvcC record's parameter sets (the first of each kind), sized by them (x19 = track).
	.equ PF_P,	0                 ; VPS, SPS, PPS: pointers, then sizes
	.equ PF_N,	24
	.equ PF_FD,	48
ps_fd:
	FRAME	2, 64
	mov	x20, x0
	add	x21, x0, x1
	mov	w22, w2
	movi	v0.16b, #0
	stp	q0, q0, [sp]
	stp	q0, q0, [sp, #32]
	cbnz	w22, Lpf_hevc
	add	x9, x20, #7               ; avcC: the length size, the SPS count, then SPS, PPS count, PPS
	cmp	x9, x21
	b.hi	Lpf_no
	ldrb	w10, [x20, #5]
	and	w10, w10, #31
	add	x9, x20, #6
1:	cbz	w10, 2f
	add	x11, x9, #2
	cmp	x11, x21
	b.hi	Lpf_no
	ldrh	w12, [x9]
	rev16	w12, w12
	ldr	x13, [sp, #(PF_P + 8)]
	cbnz	x13, 3f
	stp	x11, x12, [sp, #(PF_P + 8)] ; the first SPS (its size beside it, fixed below)
3:	add	x9, x11, x12
	sub	w10, w10, #1
	b	1b
2:	add	x11, x9, #1
	cmp	x11, x21
	b.hi	Lpf_no
	ldrb	w10, [x9]                 ; PPS count
	cbz	w10, Lpf_no
	add	x9, x9, #3
	cmp	x9, x21
	b.hi	Lpf_no
	ldrh	w12, [x11]
	rev16	w12, w12
	add	x13, x9, x12
	cmp	x13, x21
	b.hi	Lpf_no
	ldp	x13, x14, [sp, #(PF_P + 8)] ; SPS pointer and size
	cbz	x13, Lpf_no
	stp	x13, x9, [sp, #PF_P]      ; pointers: SPS, PPS
	stp	x14, x12, [sp, #PF_N]     ; sizes
	mov	x0, #0
	mov	x1, #2
	mov	x2, sp
	add	x3, sp, #PF_N
	ldrb	w4, [x20, #4]
	and	w4, w4, #3
	add	w4, w4, #1                ; NAL unit length size
	add	x5, sp, #PF_FD
	bl	_CMVideoFormatDescriptionCreateFromH264ParameterSets
	b	Lpf_made
Lpf_hevc:
	add	x9, x20, #23              ; hvcC: arrays of NAL units, each type's first kept (VPS 32, SPS 33, PPS 34)
	cmp	x9, x21
	b.hi	Lpf_no
	ldrb	w10, [x20, #22]
4:	cbz	w10, 6f
	add	x11, x9, #3
	cmp	x11, x21
	b.hi	Lpf_no
	ldrb	w12, [x9]
	and	w12, w12, #63
	ldrh	w13, [x9, #1]
	rev16	w13, w13                  ; its units
	mov	x9, x11
5:	cbz	w13, 7f
	add	x11, x9, #2
	cmp	x11, x21
	b.hi	Lpf_no
	ldrh	w14, [x9]
	rev16	w14, w14
	add	x9, x11, x14
	cmp	x9, x21
	b.hi	Lpf_no
	sub	w15, w12, #32
	cmp	w15, #3
	b.hs	8f
	lsl	x15, x15, #3
	add	x16, sp, x15
	ldr	x17, [x16]
	cbnz	x17, 8f
	str	x11, [x16]
	str	x14, [x16, #PF_N]
8:	sub	w13, w13, #1
	b	5b
7:	sub	w10, w10, #1
	b	4b
6:	ldp	x9, x10, [sp]
	ldr	x11, [sp, #16]
	cbz	x9, Lpf_no
	cbz	x10, Lpf_no
	cbz	x11, Lpf_no
	mov	x0, #0
	mov	x1, #3
	mov	x2, sp
	add	x3, sp, #PF_N
	ldrb	w4, [x20, #21]
	and	w4, w4, #3
	add	w4, w4, #1
	mov	x5, #0
	add	x6, sp, #PF_FD
	bl	_CMVideoFormatDescriptionCreateFromHEVCParameterSets
Lpf_made:
	cbnz	w0, Lpf_no
	ldr	x9, [sp, #PF_FD]
	str	x9, [x19, #TR_FD]
	bl	vid_dims
	mov	w0, #0
	b	Lret2
Lpf_no:
	mov	w0, #1
	b	Lret2

; flv_sound(context) — the sound's track, its format from its first tag and sequence start: AAC, MP3, Opus, FLAC, PCM, G.711.
	.equ FS_A,	0                 ; an AudioStreamBasicDescription
	.equ FS_CK,	48                ; a cookie made here (a dfLa box)
	.equ FS_FPP,	104               ; w: TR_MFPP's
flv_sound:
	FRAME	4, 112
	mov	x20, x0
	movi	v0.16b, #0
	stp	q0, q0, [sp]
	stp	q0, q0, [sp, #32]
	stp	q0, q0, [sp, #64]
	str	q0, [sp, #96]
	ldp	x21, x22, [x20, #FO_ATAG] ; its first tag's data
	mov	x25, #0                   ; no cookie
	mov	x26, #0
	ldrb	w9, [x21]
	and	w10, w9, #1               ; its flags: channels, bits, rate
	add	w10, w10, #1
	str	w10, [sp, #(FS_A + 28)]
	ubfx	w10, w9, #1, #1
	mov	w11, #8
	lsl	w11, w11, w10
	str	w11, [sp, #(FS_A + 32)]
	ubfx	w10, w9, #2, #2
	adr	x11, Lfs_rates
	ldr	w23, [x11, x10, lsl #2]
	lsr	w24, w9, #4               ; its format
	cmp	w24, #10
	b.eq	Lfs_aac
	cmp	w24, #2
	ccmp	w24, #14, #4, ne
	b.eq	Lfs_mp3
	cmp	w24, #3
	ccmp	w24, #0, #4, ne
	b.eq	Lfs_pcm
	cmp	w24, #7
	ccmp	w24, #8, #4, ne
	b.eq	Lfs_g711
	cmp	w24, #9
	b.ne	Lret4
	add	x9, x21, #5               ; enhanced: by its FourCC
	cmp	x9, x22
	b.hi	Lret4
	ldur	w24, [x21, #1]
	rev	w24, w24
	MOVL	w10, 0x6d703461           ; 'mp4a'
	cmp	w24, w10
	b.eq	Lfs_aac
	MOVL	w10, 0x2e6d7033           ; '.mp3': its frames 5 bytes in
	add	x21, x21, #4
	cmp	w24, w10
	b.eq	Lfs_mp3
	MOVL	w10, 0x4f707573           ; 'Opus'
	cmp	w24, w10
	b.eq	Lfs_opus
	MOVL	w10, 0x664c6143           ; 'fLaC'
	cmp	w24, w10
	b.eq	Lfs_flac
	b	Lret4
Lfs_aac:
	ldp	x0, x1, [x20, #FO_ACFG]   ; its AudioSpecificConfig: core rate, channels
	cbz	x0, Lret4
	sub	x1, x1, x0
	bl	asc_info
	cbz	w0, Lret4
	mov	w23, w0
	mov	w24, w1
	mov	w0, #'a'
	mov	w1, w23
	mov	x2, x20
	bl	flv_track
	cbz	x0, Lret4
	mov	x19, x0
	mov	w9, #1024
	str	w9, [x19, #TR_MFPP]
	ldp	x0, x1, [x20, #FO_ACFG]
	sub	x1, x1, x0
	mov	w2, w24
	mov	w3, w23
	bl	mp4a_keep
	bl	flv_take
	b	Lret4
Lfs_mp3:
	add	x0, x21, #1               ; its first frame's header: layer, version, rate, channels
	mov	x1, x22
	mov	x2, sp
	bl	mpa_info
	cbz	w0, Lret4
	mov	w23, w0
	str	wzr, [sp, #(FS_A + 32)]
	ldr	w9, [sp, #(FS_A + 20)]
	str	w9, [sp, #FS_FPP]
	b	Lfs_make
Lfs_pcm:
	TYPE	w9, 'm','c','p','l'      ; 'lpcm', little-endian
	mov	w10, #(kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked)
	ldr	w11, [sp, #(FS_A + 32)]
	cmp	w11, #8
	mov	w12, #kAudioFormatFlagIsPacked ; 8 bits: unsigned
	csel	w10, w12, w10, eq
	b	Lfs_frames
Lfs_g711:
	MOVL	w9, 0x616c6177            ; 'alaw', 'ulaw': 8 bits at 8 kHz
	MOVL	w10, 0x756c6177
	cmp	w24, #8
	csel	w9, w10, w9, eq
	mov	w11, #8
	str	w11, [sp, #(FS_A + 32)]
	mov	w23, #8000
	mov	w10, #0
Lfs_frames:
	str	w9, [sp, #(FS_A + 8)]     ; a tag's every frame a sample
	str	w10, [sp, #(FS_A + 12)]
	ldr	w11, [sp, #(FS_A + 28)]
	ldr	w12, [sp, #(FS_A + 32)]
	mul	w11, w11, w12
	lsr	w11, w11, #3
	cbz	w11, Lret4
	str	w11, [sp, #(FS_A + 16)]
	str	w11, [sp, #(FS_A + 24)]
	mov	w12, #1
	str	w12, [sp, #(FS_A + 20)]
	mov	w12, #-2
	str	w12, [sp, #FS_FPP]
	b	Lfs_make
Lfs_opus:
	ldp	x25, x26, [x20, #FO_ACFG] ; OpusHead: the cookie, and its channels
	cbz	x25, Lret4
	sub	x26, x26, x25
	cmp	x26, #19
	b.lo	Lret4
	ldrb	w9, [x25, #9]
	str	w9, [sp, #(FS_A + 28)]
	MOVL	w9, 0x6f707573
	str	w9, [sp, #(FS_A + 8)]
	mov	w9, #960
	str	w9, [sp, #(FS_A + 20)]
	str	wzr, [sp, #(FS_A + 32)]
	mov	w9, #-1
	str	w9, [sp, #FS_FPP]
	MOVL	w23, 48000
	b	Lfs_make
Lfs_flac:
	ldp	x24, x25, [x20, #FO_ACFG] ; STREAMINFO's block, after a "fLaC" mark if there is one
	cbz	x24, Lret4
	sub	x9, x25, x24
	cmp	x9, #38
	b.lo	Lret4
	ldr	w10, [x24]
	TYPE	w11, 'f','L','a','C'
	cmp	w10, w11
	b.ne	1f
	cmp	x9, #42
	b.lo	Lret4
	add	x24, x24, #4
1:	add	x24, x24, #4
	ldrb	w9, [x24, #10]            ; the rate (20 bits) and channels (3)
	ldrb	w10, [x24, #11]
	ldrb	w11, [x24, #12]
	lsl	w23, w9, #12
	orr	w23, w23, w10, lsl #4
	orr	w23, w23, w11, lsr #4
	ubfx	w9, w11, #1, #3
	add	w9, w9, #1
	str	w9, [sp, #(FS_A + 28)]
	MOVL	w9, 0x666c6163
	str	w9, [sp, #(FS_A + 8)]
	mov	x0, x24
	add	x1, sp, #FS_A
	add	x2, sp, #FS_CK
	bl	flac_fmt
	str	w0, [sp, #FS_FPP]
	str	wzr, [sp, #(FS_A + 32)]
	add	x25, sp, #FS_CK
	mov	x26, #50
Lfs_make:
	ucvtf	d0, w23
	str	d0, [sp, #FS_A]
	mov	w0, #'a'
	mov	w1, w23
	mov	x2, x20
	bl	flv_track
	cbz	x0, Lret4
	mov	x19, x0
	ldr	w9, [sp, #FS_FPP]
	str	w9, [x19, #TR_MFPP]
	ldr	w9, [sp, #(FS_A + 24)]
	str	w9, [x19, #TR_FIXED]      ; PCM's bytes per frame
	mov	x0, sp
	mov	x1, x25
	mov	x2, x26
	bl	snd_keep
	bl	flv_take
	b	Lret4
Lfs_rates:
	.long	5512, 11025, 22050, 44100

; asc_info(config, length) -> w0 = an AudioSpecificConfig's (core) rate, w1 = its channels; 0 for one with an escaped type or rate.
asc_info:
	cmp	x1, #2
	b.lo	1f
	ldrb	w9, [x0]
	ldrb	w10, [x0, #1]
	lsr	w11, w9, #3
	cmp	w11, #31
	b.eq	1f
	and	w11, w9, #7
	lsl	w11, w11, #1
	orr	w11, w11, w10, lsr #7     ; its rate's index
	cmp	w11, #13
	b.hs	1f
	GADDR	x12, Lk_rates
	ldr	w0, [x12, x11, lsl #2]
	ubfx	w1, w10, #3, #4           ; channels; 0 (a PCE's): stereo, 7: eight
	cmp	w1, #0
	mov	w12, #2
	csel	w1, w12, w1, eq
	cmp	w1, #7
	mov	w12, #8
	csel	w1, w12, w1, eq
	ret
1:	mov	w0, #0
	ret

; mpa_info(frame, end, format) -> w0 = an MPEG audio frame's rate, its layer's format, frames per packet and channels set in the AudioStreamBasicDescription; 0 for no frame header.
mpa_info:
	add	x9, x0, #4
	cmp	x9, x1
	b.hi	1f
	ldrb	w9, [x0]
	ldrb	w10, [x0, #1]
	ldrb	w11, [x0, #2]
	ldrb	w12, [x0, #3]
	and	w13, w10, #0xe0
	mov	w15, #0xe0
	cmp	w9, #0xff
	ccmp	w13, w15, #0, eq
	b.ne	1f
	ubfx	w13, w10, #3, #2          ; version: 3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5
	cmp	w13, #1
	b.eq	1f
	ubfx	w14, w10, #1, #2          ; layer: 1 III, 2 II, 3 I
	cbz	w14, 1f
	ubfx	w15, w11, #2, #2
	cmp	w15, #3
	b.eq	1f
	adr	x16, Lmpa
	ldr	w0, [x16, x15, lsl #2]
	cmp	w13, #2
	cset	w15, eq
	cmp	w13, #0
	mov	w16, #2
	csel	w15, w16, w15, eq
	lsr	w0, w0, w15               ; MPEG-2 half, MPEG-2.5 a quarter
	lsr	w12, w12, #6
	cmp	w12, #3
	mov	w12, #2
	cinc	w12, w12, ne
	sub	w12, w12, #1              ; mono: 1, else 2
	str	w12, [x2, #28]
	adr	x16, Lmpa + 12
	sub	w14, w14, #1
	add	x16, x16, x14, lsl #3
	ldr	w9, [x16]                 ; '.mp3', '.mp2', '.mp1'
	str	w9, [x2, #8]
	ldr	w9, [x16, #4]             ; and frames
	cmp	w13, #3
	ccmp	w14, #0, #0, ne
	b.ne	2f
	mov	w9, #576                  ; layer III of MPEG-2 and 2.5
2:	str	w9, [x2, #20]
	ret
1:	mov	w0, #0
	ret
Lmpa:
	.long	44100, 48000, 32000
	.long	0x2e6d7033, 1152, 0x2e6d7032, 1152, 0x2e6d7031, 384

; flv_next -> w0 = 1 with the track's next frame (its next tag of a media packet), 0 at the end, where TR_N stops the track (x19 = track).
flv_next:
	FRAME	4, 48
	bl	xs_win
	mov	x20, x0
	add	x21, x0, x1
	str	w2, [sp, #MN_GO]          ; more may come
	ldr	x22, [x19, #TR_XEND]
Lfn_tag:
	add	x23, x20, x22             ; the tag: valid and all in; one that looks like a tag cut by the bytes so far waits; anything else is passed byte by byte
	mov	x0, x23
	mov	x1, x21
	bl	flv_ok
	cbnz	w0, 1f
	add	x9, x23, #11
	cmp	x9, x21
	b.hi	Lfn_edge                  ; too few bytes to tell
	ldrb	w9, [x23]                 ; a tag's type, stream 0
	cmp	w9, #8
	ccmp	w9, #9, #4, ne
	ccmp	w9, #18, #4, ne
	b.ne	2f
	ldr	w9, [x23, #7]
	lsr	w9, w9, #8
	cbnz	w9, 2f
	ldr	w9, [x23]
	rev	w9, w9
	and	x9, x9, #0xffffff
	add	x9, x9, x23
	add	x9, x9, #15
	cmp	x9, x21
	b.hi	Lfn_edge                  ; it runs past them
2:	add	x22, x22, #1
	b	Lfn_tag
1:	ldr	w9, [x23]
	rev	w9, w9
	and	x9, x9, #0xffffff
	add	x24, x23, #11             ; its data
	add	x25, x24, x9              ; and their end
	add	x22, x22, #15             ; the next tag
	add	x22, x22, x9
	ldrb	w10, [x23]
	ldr	w11, [x19, #TR_MNUM]
	cmp	w10, w11                  ; this track's type, not filtered (encrypted)
	b.ne	Lfn_tag
	cmp	x24, x25
	b.hs	Lfn_tag
	ldrb	w12, [x24]
	mov	x26, #0                   ; the composition offset
	mov	w13, #1                   ; sync
	ldr	w9, [x19, #TR_KIND]
	cmp	w9, #'v'
	b.ne	Lfn_sound
	ubfx	w13, w12, #4, #3          ; the frame type: 1 key, 4 generated key, 5 a command
	cmp	w13, #5
	b.eq	Lfn_tag
	cmp	w13, #1
	ccmp	w13, #4, #4, ne
	cset	w13, eq
	tbnz	w12, #7, 1f
	ldrb	w9, [x24, #1]             ; legacy: a NAL unit packet, its composition time
	cmp	w9, #1
	b.ne	Lfn_tag
	add	x9, x24, #5
	cmp	x9, x25
	b.hi	Lfn_tag
	add	x10, x24, #2
	b	3f
1:	and	w9, w12, #15              ; enhanced: CodedFrames (a composition time for AVC and HEVC) or CodedFramesX
	add	x10, x24, #5
	cmp	w9, #3
	b.eq	4f
	cmp	w9, #1
	b.ne	Lfn_tag
	ldur	w11, [x24, #1]
	rev	w11, w11
	MOVL	w14, 0x61766331
	cmp	w11, w14
	MOVL	w14, 0x68766331
	ccmp	w11, w14, #4, ne
	b.ne	4f
	add	x9, x24, #8
	cmp	x9, x25
	b.hi	Lfn_tag
3:	ldrb	w11, [x10]                ; SI24, ms
	ldrb	w14, [x10, #1]
	ldrb	w15, [x10, #2]
	lsl	w11, w11, #16
	orr	w11, w11, w14, lsl #8
	orr	w11, w11, w15
	sbfx	x26, x11, #0, #24
	add	x10, x10, #3
4:	mov	x24, x10
	b	Lfn_frame
Lfn_sound:
	lsr	w9, w12, #4
	add	x10, x24, #1              ; one byte of flags
	cmp	w9, #10
	b.ne	5f
	ldrb	w9, [x24, #1]             ; AAC: a raw frame
	cmp	w9, #1
	b.ne	Lfn_tag
	add	x10, x24, #2
	b	6f
5:	cmp	w9, #9
	b.ne	6f
	and	w9, w12, #15              ; enhanced: CodedFrames
	cmp	w9, #1
	b.ne	Lfn_tag
	add	x10, x24, #5
6:	mov	x24, x10
Lfn_frame:
	cmp	x24, x25
	b.hs	Lfn_tag
	sub	x9, x24, x20
	str	x9, [x19, #TR_OFF]
	sub	x9, x25, x24
	str	w9, [x19, #TR_XSIZE]
	str	x22, [x19, #TR_XEND]
	str	w13, [x19, #TR_XSYNC]
	sub	x9, x23, x20
	str	x9, [x19, #TR_XKEY]
	ldr	w9, [x23, #4]             ; its time: 24 bits, then the 8 above them (ms)
	rev	w9, w9
	lsr	w10, w9, #8
	orr	w10, w10, w9, lsl #24
	sxtw	x10, w10
	ldr	d1, [x19, #TR_MFAC]
	scvtf	d0, x10
	fmul	d0, d0, d1
	fcvtns	x10, d0
	scvtf	d0, x26
	fmul	d0, d0, d1
	fcvtns	x26, d0
	str	w26, [x19, #TR_XCTS]
	bl	xs_est
	ldr	w11, [x19, #TR_MDDUR]
	b	Lmn_dur
Lfn_edge:
	mov	x24, x22
	b	Lmn_edge

; flv_start(moment) — the cursor at the track's first frame from the tag its index gives for that moment, or that halving the file finds (track units; sound looks 200 ms earlier), a picture's at its first sync frame (x19 = track).
flv_start:
	FRAME	4
	bl	xs_moment
	fcvtzs	x22, d0                   ; the moment, ms
	bl	xs_win
	mov	x20, x0
	add	x21, x0, x1
	ldr	x23, [x19, #TR_MCL]       ; the first tag, unless the index says a later one
	ldp	x24, x25, [x19, #TR_MCUES] ; positions and times: counts, then numbers of 9 bytes
	cbz	x24, Lfs_halve
	ldur	w26, [x24, #1]
	rev	w26, w26
	add	x24, x24, #5
	add	x25, x25, #5
	MOVL	w9, 1000
	ucvtf	d2, w9
2:	cbz	w26, Lks_at
	ldur	x9, [x25, #1]
	rev	x9, x9
	fmov	d0, x9
	fmul	d0, d0, d2
	fcvtzs	x9, d0
	cmp	x9, x22
	b.gt	Lks_at
	ldur	x9, [x24, #1]
	rev	x9, x9
	fmov	d0, x9
	fcvtzu	x9, d0
	ldr	w10, [x19, #TR_SRC]       ; a stream's is checked as it comes
	cbnz	w10, 4f
	sub	x10, x21, x20
	cmp	x9, x10
	b.hs	3f
	add	x0, x20, x9
	mov	x1, x21
	bl	flv_ok
	cbz	w0, 3f
4:	mov	x23, x9
3:	add	x24, x24, #9
	add	x25, x25, #9
	sub	w26, w26, #1
	b	2b
Lfs_halve:
	ldr	w9, [x19, #TR_SRC]
	cbz	w9, Lfs_split
	scvtf	d0, x22                   ; a stream with no index: the moment's share of its length (the next tag from there)
	bl	xs_guess
	cmp	x0, x23
	csel	x23, x0, x23, hi
	b	Lks_at
Lfs_split:
	ldr	x24, [x19, #TR_MCL]       ; no index: a key frame by halving (any tag for sound alone)
	sub	x25, x21, x20
4:	sub	x9, x25, x24
	cmp	x9, #0x10000
	b.lo	Lks_at
	add	x0, x24, x9, lsr #1
	mov	x1, x25
	bl	flv_key                   ; x0 = the first key frame's tag at or after it, x1 = its time; 0 if none before x25
	cbz	x0, 5f
	cmp	x1, x22
	b.gt	5f
	mov	x23, x0
	add	x24, x0, #1
	b	4b
5:	sub	x9, x25, x24
	add	x25, x24, x9, lsr #1
	b	4b

; flv_ok(tag, end) -> w0 = 1 if a valid tag starts there: a known type, stream 0, and the size after it its own (x9 kept).
flv_ok:
	add	x10, x0, #15
	cmp	x10, x1
	b.hi	1f
	ldrb	w10, [x0]
	cmp	w10, #8
	ccmp	w10, #9, #4, ne
	ccmp	w10, #18, #4, ne
	b.ne	1f
	ldr	w10, [x0, #7]             ; stream ID
	lsr	w10, w10, #8
	cbnz	w10, 1f
	ldr	w10, [x0]
	rev	w10, w10
	and	x10, x10, #0xffffff
	add	x11, x0, #11
	add	x11, x11, x10
	add	x12, x11, #4
	cmp	x12, x1
	b.hi	1f
	ldr	w12, [x11]
	rev	w12, w12
	add	w10, w10, #11
	cmp	w12, w10
	cset	w0, eq
	ret
1:	mov	w0, #0
	ret

; flv_key(offset, limit) -> x0 = the offset of the first tag after offset that is a picture's key frame (any tag for sound), x1 = its time (ms); 0 if none before limit (x19 = track, x20 = the file's bytes, x21 = their end).
flv_key:
	FRAME	3
	add	x23, x20, x0
	add	x24, x20, x1
1:	cmp	x23, x24                  ; a valid tag first: a halfway point is anywhere
	b.hs	Lfk_no
	mov	x0, x23
	mov	x1, x21
	bl	flv_ok
	cbnz	w0, 2f
	add	x23, x23, #1
	b	1b
2:	mov	w15, #4096                ; then tag by tag
3:	cmp	x23, x24
	b.hs	Lfk_no
	subs	w15, w15, #1
	b.lo	Lfk_no
	add	x9, x23, #12
	cmp	x9, x21
	b.hi	Lfk_no
	ldr	w11, [x23]
	rev	w11, w11
	and	x11, x11, #0xffffff
	ldr	w12, [x19, #TR_KIND]
	cmp	w12, #'v'
	b.ne	4f
	ldrb	w10, [x23]
	ldrb	w12, [x23, #11]
	ubfx	w12, w12, #4, #3
	cmp	w10, #9
	ccmp	w12, #1, #0, eq
	b.eq	4f
	add	x23, x23, #15
	add	x23, x23, x11
	b	3b
4:	ldr	w9, [x23, #4]             ; its time
	rev	w9, w9
	lsr	w10, w9, #8
	orr	w10, w10, w9, lsl #24
	sxtw	x1, w10
	sub	x0, x23, x20
	b	Lret3
Lfk_no:
	mov	x0, #0
	b	Lret3

; ---- Matroska and FLV over the network: the stream's arena is the cursors' file ----

; xs_sink(stream, bytes, length) — the bytes into the arena (or the Cues, collected for a seek), the tracks once the header is in, then every frame all in to its track's queue.
xs_sink:
	FRAME	3, 0, 1
	mov	x21, x2
	ldr	w9, [x19, #ST_XMODE]
	cbnz	w9, Lxk_cues
Lxk_more:
	cbz	x21, Lret3
	ldp	x9, x10, [x19, #ST_ARN]   ; used, room
	cmp	x9, x10
	b.lo	2f
	ldr	w12, [x19, #ST_XHEAD]
	cbnz	w12, 1f
	mov	x10, #(ARENA_MAX << 3)
	cmp	x9, x10
	b.hs	Lxk_fail
1:	mov	x9, #ARENA_MAX
	str	x9, [x19, #ST_LEFT]
	mov	x0, x19
	bl	arena_new
	cbz	x0, Lxk_fail
	ldp	x9, x10, [x19, #ST_ARN]
2:	sub	x10, x10, x9
	cmp	x21, x10
	csel	x22, x21, x10, lo
	bl	ar_put
	ldr	x9, [x19, #ST_SPOS]
	add	x9, x9, x22
	str	x9, [x19, #ST_SPOS]
	add	x20, x20, x22
	sub	x21, x21, x22
	ldr	w9, [x19, #ST_XHEAD]
	cbnz	w9, 3f
	mov	x0, x19
	bl	xs_head
	cmp	w0, #1
	b.lt	4f
	b.ne	Lret3                     ; it moved: the rest is not wanted
3:	mov	x0, x19
	bl	emit
	b	Lxk_more
4:	cbz	w0, Lxk_fail              ; -1: more first
	b	Lxk_more
Lxk_fail:
	mov	x0, x19                   ; not playable: AVPlayer gets it
	bl	st_reset
	b	Lpu_end
Lxk_cues:
	ldr	x0, [x19, #ST_XIDX]       ; the Cues as they come, until their element is whole
	ldr	x22, [x19, #ST_XIDXN]
	add	x1, x22, x21
	mov	x9, #BOX_MAX
	cmp	x1, x9
	b.hi	Lxk_nocues
	bl	_realloc
	cbz	x0, Lxk_nocues
	str	x0, [x19, #ST_XIDX]
	add	x0, x0, x22
	mov	x1, x20
	mov	x2, x21
	bl	_memcpy
	add	x22, x22, x21
	str	x22, [x19, #ST_XIDXN]
	ldr	x0, [x19, #ST_XIDX]
	add	x1, x0, x22
	bl	el_head
	cbz	x0, Lret3                 ; its header not all in yet
	MOVL	w9, 0x1C53BB6B
	cmp	w2, w9
	b.ne	Lxk_nocues
	add	x9, x0, x3
	cmp	x9, x1
	b.hi	Lret3                     ; not whole yet
	mov	x1, x9
	bl	xs_index
	b	Lxk_seek
Lxk_nocues:
	ldr	x0, [x19, #ST_XIDX]
	bl	_free
	str	xzr, [x19, #ST_XIDX]
	str	xzr, [x19, #ST_XIDXN]
Lxk_seek:
	str	xzr, [x19, #ST_XCUEP]     ; read, or none: the seek goes on
	str	wzr, [x19, #ST_XMODE]
	mov	x0, x19
	ldr	x1, [x19, #ST_PEND]
	bl	st_seek
	b	Lret3

; xs_index(data, end) — the stream's tracks read these Cues (x19 = stream).
xs_index:
	ldr	x9, [x19, #ST_TR]
	cbz	x9, 1f
	stp	x0, x1, [x9, #TR_MCUES]
1:	ldr	x9, [x19, #(ST_TR + 8)]
	cbz	x9, 2f
	stp	x0, x1, [x9, #TR_MCUES]
2:	ret

; xs_nocues(stream) — the Cues' request ended before they were whole: the seek waiting for them goes on without.
xs_nocues:
	FRAME	3, 0, 1
	b	Lxk_nocues
; xs_head(stream) -> w0 = 1 with its tracks made and attached, 2 if then it moved to a seek's target, 0 for no playable media, -1 for more first.
xs_head:
	FRAME	1, 0, 1
	ldr	w9, [x19, #ST_KIND]
	mov	x0, x19
	cmp	w9, #3
	b.ne	1f
	bl	mkv_open
	b	2f
1:	bl	flv_open
2:	cmp	w0, #1
	b.ne	Lret1
	str	w0, [x19, #ST_XHEAD]
	ldr	x1, [x27, #E_TGTMS]       ; a seek came first: there
	cbz	x1, Lret1
	mov	x0, x19
	bl	st_seek
	mov	w0, #2
	b	Lret1

Lxe_loop:
	mov	x21, #0                   ; the track whose frame comes first in the file
	mov	x22, #-1
	ldr	x19, [x20, #ST_TR]
	bl	Lxe_one
	ldr	x19, [x20, #(ST_TR + 8)]
	bl	Lxe_one
	cbz	x21, Lret2
	mov	x19, x21
	bl	cur_size
	ldp	x1, x9, [x20, #ST_ARPOS]
	subs	x10, x22, x1
	b.lo	1f
	add	x10, x10, x0
	cmp	x10, x9
	b.hi	Lret2
	bl	aonly_drop
	b.eq	1f
	ldr	x0, [x20, #ST_ARBB]
	bl	cur_sample
	cbz	x0, Lxe_loop
	bl	q_push
	b	Lxe_loop
1:	bl	cur_step                  ; Audio Only: not this picture
	b	Lxe_loop
; Lxe_one — track x19 (0: none) reads on if it waited; then, if it has a frame, the earliest so far (x21, its offset x22).
Lxe_one:
	cbz	x19, 2f
	stp	x29, x30, [sp, #-16]!
	ldr	w9, [x19, #TR_MWAIT]
	cbz	w9, 1f
	bl	xs_step
1:	bl	q_wait
	ldp	x29, x30, [sp], #16
	b.hs	2f
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	cmp	w9, w10
	b.hs	3f
	ldr	x9, [x19, #TR_OFF]
	cmp	x9, x22
	b.hs	2f
	mov	x21, x19
	mov	x22, x9
2:	ret
3:	ldr	w9, [x19, #TR_MWAIT]
	cbnz	w9, 2b
	mov	x9, #(1 << 52)
	str	x9, [x19, #TR_LAST]
	ret

; xs_cursors(stream) -> x0 = where the stream reads from: its tracks' cursors at their targets, the earliest of them (0 with none).
xs_cursors:
	FRAME	2, 0, 1
	mov	x20, x19
	mov	x21, #-1
	ldr	x19, [x20, #ST_TR]
	bl	1f
	ldr	x19, [x20, #(ST_TR + 8)]
	bl	1f
	cmn	x21, #1
	csel	x0, xzr, x21, eq
	b	Lret2
1:	cbz	x19, 3f
	stp	x29, x30, [sp, #-16]!
	bl	trk_seek
	ldp	x29, x30, [sp], #16
	ldr	w9, [x19, #TR_I]
	ldr	w10, [x19, #TR_N]
	ldr	x11, [x19, #TR_OFF]
	cmp	w9, w10
	b.lo	2f
	ldr	x11, [x19, #TR_XEND]      ; waiting: from where it reads on
2:	cmp	x11, x21
	csel	x21, x11, x21, lo
3:	ret

; st_total(stream, task) — a range's answer: the stream's whole length from its Content-Range, unless known.
st_total:
	FRAME	2, 0, 1
	ldr	x9, [x19, #ST_XLEN]
	cbnz	x9, Lret2
	adr	x0, Ls_crange
	bl	mkstr
	mov	x21, x0
	mov	x0, x20
	SEND	S_response
	mov	x2, x21
	SEND	S_valueForHTTPHeaderField_
	SEND	S_UTF8String
	cbz	x0, Lret2
	mov	w1, #'/'
	bl	_strchr
	cbz	x0, Lret2
	add	x0, x0, #1
	bl	strtol10
	str	x0, [x19, #ST_XLEN]
	b	Lret2
Ls_crange:	.asciz	"Content-Range"
	.p2align 2


; ---- Tables ----

	.section __DATA,__data
	.p2align 3
	.equ X_REGULAR,	(F_NSFontWeightRegular - B_REG) >> 3
	.equ X_MEDIUM,	(F_NSFontWeightMedium - B_REG) >> 3
	.equ X_SEMIBOLD,	(F_NSFontWeightSemibold - B_REG) >> 3
	.equ G_SEP,	G_T3                  ; a separator item

; Services, the colors, the controller (every action's target, the app and window delegate), the canvas, the menus (Edit enables Cmd-V), the window and its views.
Lprog_build:
	CALL	F_objc_autoreleasePoolPush
	CALL	F_dispatch_get_global_queue, "=II"
	.byte	QOS_CLASS_USER_INITIATED, 0
	STO	G_WORKQ
	CALL	F_dispatch_async_f, "OIP"
	.byte	G_WORKQ >> 3, 0
	.long	av1_check - Lvm_base
	CALL	F_dispatch_queue_attr_make_with_autorelease_frequency, "=II"
	.byte	0, 1                      ; serial, a pool per work item
	CALL	F_dispatch_queue_attr_make_with_qos_class, "=VII"
	.byte	QOS_CLASS_USER_INTERACTIVE, 0
	CALL	F_dispatch_queue_create, "=CV"
	.asciz	"mia.media"
	STO	G_MEDIAQ
	CALL	F_dispatch_queue_create, "=CI"
	.asciz	"mia.clock"
	.byte	0
	STO	G_CLOCKQ

	; Flat colors: near-black, two surfaces, one yellow accent.
	COLOR	G_BGC, 21, 21, 21, 255
	COLOR	G_SURF, 28, 28, 28, 240
	COLOR	G_SURF2, 39, 39, 39, 255
	COLOR	G_YEL, 244, 253, 55, 255
	COLOR	G_TEXT, 229, 229, 229, 255
	COLOR	G_SECOND, 160, 160, 160, 255
	COLOR	G_RED, 229, 57, 53, 255

	CLS	NSObject
	CALL	F_objc_allocateClassPair, "=VCI"
	.asciz	"MIAController"
	.byte	0
	STO	G_T0
	METHOD	S_act_play_, act_play
	METHOD	S_act_toggle_, act_toggle
	METHOD	S_act_stop_, act_stop
	METHOD	S_act_back_, act_back
	METHOD	S_act_fwd_, act_fwd
	METHOD	S_act_vol_, act_vol
	METHOD	S_act_volup_, act_volup
	METHOD	S_act_voldown_, act_voldown
	METHOD	S_act_mute_, act_mute
	METHOD	S_act_seek_, act_seek
	METHOD	S_act_tick_, act_tick
	METHOD	S_act_focus_, act_focus
	METHOD	S_act_open_, act_open
	METHOD	S_act_aonly_, act_aonly
	METHOD	S_menuNeedsUpdate_, act_options
	METHOD	S_act_speed_, act_speed
	METHOD	S_act_option_, act_option
	METHOD	S_act_pip_, act_pip
	METHOD	S_routePickerViewWillBeginPresentingRoutes_, air_prepare
	METHOD	S_pictureInPictureController_setPlaying_, pip_play, "v@:@B"
	METHOD	S_pictureInPictureControllerTimeRangeForPlayback_, pip_range, "{?={?=qiIq}{?=qiIq}}@:@"
	METHOD	S_pictureInPictureControllerIsPlaybackPaused_, pip_paused, "B@:@"
	METHOD	S_pictureInPictureController_didTransitionToRenderSize_, imp_yes, "v@:@{?=ii}"
	METHOD	S_pictureInPictureController_skipByInterval_completionHandler_, pip_skip, "v@:@{?=qiIq}@?"
	METHOD	S_windowDidResize_, act_layout
	METHOD	S_control_textView_doCommandBySelector_, act_urlcmd, "B@:@@:"
	METHOD	S_application_openURLs_, act_openurls, "v@:@@"
	METHOD	S_URLSession_dataTask_didReceiveData_, act_netdata, "v@:@@@"
	METHOD	S_URLSession_task_didCompleteWithError_, act_netdone, "v@:@@@"
	METHOD	S_applicationShouldTerminateAfterLastWindowClosed_, imp_yes, "B@:@"
	CALL	F_objc_registerClassPair, "O"
	.byte	G_T0 >> 3
	LD	G_T0
	MSG	S_new, "="
	STO	G_CTRL

	; The canvas: the window's content; it takes the keyboard, drops and the mouse.
	CLS	NSView
	CALL	F_objc_allocateClassPair, "=VCI"
	.asciz	"MIAView"
	.byte	0
	STO	G_T0
	METHOD	S_acceptsFirstResponder, imp_yes, "B@:"
	METHOD	S_mouseMoved_, act_moved
	METHOD	S_mouseDown_, act_click
	METHOD	S_keyDown_, act_key
	METHOD	S_draggingEntered_, imp_yes, "Q@:@"  ; NSDragOperationCopy
	METHOD	S_performDragOperation_, act_drop, "B@:@"
	CALL	F_objc_registerClassPair, "O"
	.byte	G_T0 >> 3
	LD	G_T0
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=R"
	RC	0, 0, WIN_W, WIN_H
	STO	G_CONTENT

	CLS	NSApplication
	MSG	S_sharedApplication, "="
	STO	G_APP
	MSG	S_setActivationPolicy_, "I"
	.byte	0                         ; regular
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3

	CLS	NSWindow
	MSG	S_alloc, "="
	MSG	S_initWithContentRect_styleMask_backing_defer_, "=RXII"
	RC	0, 0, WIN_W, WIN_H
	.long	WIN_STYLE
	.byte	2, 0                      ; buffered, not deferred
	STO	G_WIN
	MSG	S_setTitle_, "S"          ; for the Window menu and Mission Control
	.asciz	"MIA"
	MSG	S_setTitlebarAppearsTransparent_, "I" ; content flows under it
	.byte	1
	MSG	S_setMovableByWindowBackground_, "I"
	.byte	1
	MSG	S_setTitleVisibility_, "I"
	.byte	1                         ; hidden: the title bar holds only the window buttons
	MSG	S_setBackgroundColor_, "O"
	.byte	G_BGC >> 3
	MSG	S_setCollectionBehavior_, "I"
	.byte	FULL_SCREEN_PRIMARY
	MSG	S_setContentMinSize_, "DD"
	.short	WIN_W * 4, WIN_H * 4
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setContentView_, "O"
	.byte	G_CONTENT >> 3
	CLS	NSAppearance
	MSG	S_appearanceNamed_, "=S"
	.asciz	"NSAppearanceNameDarkAqua"
	STO	G_T0
	LD	G_WIN
	MSG	S_setAppearance_, "O"
	.byte	G_T0 >> 3
	CLS	NSTrackingArea            ; mouse moves bring the controls back
	MSG	S_alloc, "="
	MSG	S_initWithRect_options_owner_userInfo_, "=RXOI"
	RC	0, 0, WIN_W, WIN_H
	.long	TRACK_OPTIONS
	.byte	G_CONTENT >> 3, 0
	STO	G_T1
	LD	G_CONTENT
	MSG	S_addTrackingArea_, "O"
	.byte	G_T1 >> 3

	OP_END

; The stage's views, made once the window is on screen.
Lprog_stage:
	LD	G_CONTENT                 ; the views are placed at the window's least size
	MSG	S_setFrameSize_, "DD"
	.short	WIN_W * 4, WIN_H * 4
	CLS	AVPlayer                  ; This Mac's player
	MSG	S_new, "="
	STO	G_PLAYER
	CLS	NSString                  ; drops: files, links and text
	MSG	S_stringWithUTF8String_, "=C"
	.asciz	"public.file-url public.url public.utf8-plain-text"
	MSG	S_componentsSeparatedByString_, "=S"
	.asciz	" "
	STO	G_T1
	LD	G_CONTENT
	MSG	S_registerForDraggedTypes_, "O"
	.byte	G_T1 >> 3
	CLS	NSMenu
	MSG	S_new, "="
	STO	G_T0                      ; the menu bar
	LD	G_APP
	MSG	S_setMainMenu_, "O"
	.byte	G_T0 >> 3
	SUBMENU	"MIA"
	ITEM	"About MIA", S_orderFrontStandardAboutPanel_, ""
	MASK	0
	SEP
	ITEM	"Hide MIA", S_hide_, "h"
	ITEM	"Hide Others", S_hideOtherApplications_, "h"
	MASK	0x180000
	ITEM	"Show All", S_unhideAllApplications_, ""
	MASK	0
	SEP
	ITEM	"Quit MIA", S_terminate_, "q"
	SUBMENU	"File"
	ITEM	"Open\342\200\246", S_act_open_, "o"
	ITEM	"Open from URL\342\200\246", S_act_focus_, "l"
	SEP
	ITEM	"Close", S_performClose_, "w"
	SUBMENU	"Edit"
	ITEM	"Undo", S_undo_, "z"
	ITEM	"Redo", S_redo_, "z"
	MASK	0x120000
	SEP
	ITEM	"Cut", S_cut_, "x"
	ITEM	"Copy", S_copy_, "c"
	ITEM	"Paste", S_paste_, "v"
	ITEM	"Select All", S_selectAll_, "a"
	SUBMENU	"Playback"
	ITEM	"Play/Pause", S_act_toggle_, " "  ; Space, only when not typing a link
	MASK	0
	ITEM	"Stop", S_act_stop_, "."
	SEP
	ITEM	"Back 10 Seconds", S_act_back_, "\357\234\202"
	ITEM	"Forward 10 Seconds", S_act_fwd_, "\357\234\203"
	SEP
	ITEM	"Volume Up", S_act_volup_, "\357\234\200"
	ITEM	"Volume Down", S_act_voldown_, "\357\234\201"
	ITEM	"Mute", S_act_mute_, "\357\234\201"
	MASK	0x180000
	SEP
	ITEM	"Audio Only", S_act_aonly_, "a"
	MASK	0x180000
	STO	G_AOITEM
	NESTED	"Speed"
	SPEED	"0.5\303\227", 50
	SPEED	"0.75\303\227", 75
	SPEED	"1\303\227", 100
	MSG	S_setState_, "I"          ; normal speed to begin with
	.byte	1
	SPEED	"1.25\303\227", 125
	SPEED	"1.5\303\227", 150
	SPEED	"2\303\227", 200
	SUBMENU	"View"
	LD	G_T1
	MSG	S_addItemWithTitle_action_keyEquivalent_, "=SLS"
	.asciz	"Enter Full Screen", "toggleFullScreen:", "f"
	MASK	0x140000
	ITEM	"Picture in Picture", S_act_pip_, "p"
	MASK	0x180000
	SEP
	NESTED	"Subtitles"
	STO	G_SUBMENU                 ; the item's legible options; Audio Track lists its audible ones
	MSG	S_setDelegate_, "O"       ; filled as they open
	.byte	G_CTRL >> 3
	NESTED	"Audio Track"
	MSG	S_setDelegate_, "O"
	.byte	G_CTRL >> 3
	SUBMENU	"Window"
	ITEM	"Minimize", S_performMiniaturize_, "m"
	ITEM	"Zoom", S_performZoom_, ""
	LD	G_APP
	MSG	S_setWindowsMenu_, "O"
	.byte	G_T1 >> 3
	; The pictures, fitted to the window: the engine's (its layer comes from the media queue), then AVPlayer's.
	NEWV	NSView, 0, 0, WIN_W, WIN_H
	STO	G_SBV
	MASKV	AR_WIDTH | AR_HEIGHT
	MSG	S_setHidden_, "I"
	.byte	1
	CLS	AVPlayerLayer
	MSG	S_playerLayerWithPlayer_, "=O"
	.byte	G_PLAYER >> 3
	STO	G_T1
	NEWV	NSView, 0, 0, WIN_W, WIN_H
	STO	G_VIDEO
	MSG	S_setLayer_, "O"
	.byte	G_T1 >> 3
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MASKV	AR_WIDTH | AR_HEIGHT
	MSG	S_setHidden_, "I"
	.byte	1

	; The artwork card (placed by layout_stage), with a music note while it has no image.
	CLS	CALayer
	MSG	S_layer, "="
	MSG	S_setContentsGravity_, "S"
	.asciz	"resizeAspectFill"
	STO	G_T0
	NEWV	NSView, 0, 0, 96, 96
	STO	G_ART
	MSG	S_setLayer_, "O"
	.byte	G_T0 >> 3
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MSG	S_setClipsToBounds_, "I"  ; AppKit mirrors it into masksToBounds
	.byte	1
	MSG	S_setHidden_, "I"
	.byte	1
	LAYERBG	G_SURF2, ART_RADIUS
	CLS	NSImageSymbolConfiguration
	MSG	S_configurationWithPointSize_weight_, "=DF"
	.short	56 * 4
	.byte	X_REGULAR
	STO	G_T0
	IMG	G_T2, "music.note", "No artwork"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T2 >> 3
	STO	G_NOTE
	MSG	S_setSymbolConfiguration_, "O"
	.byte	G_T0 >> 3
	MSG	S_setContentTintColor_, "O"
	.byte	G_SECOND >> 3
	MSG	S_setHidden_, "I"
	.byte	1
	ADDV

	; A spinner while a link resolves.
	NEWV	NSProgressIndicator, 0, 0, SPIN_S, SPIN_S
	STO	G_SPIN
	MSG	S_setStyle_, "I"
	.byte	1                         ; spinning
	MSG	S_setDisplayedWhenStopped_, "I"
	.byte	0

	; Status line under the title bar: errors in red, hints in grey.
	CLS	NSTextField
	MSG	S_labelWithString_, "=S"
	.asciz	""
	STO	G_STATUS
	MSG	S_setFrame_, "R"
	RC	80, STATUS_T, WIN_W - 160, LABEL_H
	FONT	S_systemFontOfSize_weight_, 12, X_REGULAR
	LD	G_STATUS
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setAlignment_, "I"
	.byte	1                         ; centered
	MSG	S_setLineBreakMode_, "I"
	.byte	4
	MASKV	AR_WIDTH | AR_BOTTOM
	ADDV

	; The control bar, floating at the bottom: progress, then the track, the transport, the sound and where it plays.
	NEWV	NSView, BAR_M, WIN_H - BAR_M - BAR_H, BAR_W, BAR_H
	STO	G_BAR
	MASKV	AR_WIDTH | AR_TOP
	LAYERBG	G_SURF, 16
	FONT	S_monospacedDigitSystemFontOfSize_weight_, 11, X_MEDIUM
	LABELIN	G_CUR, G_BAR, "", 16, ROW1_Y + 2, TIME_W, LABEL_H, 0, G_SECOND, AR_RIGHT
	LABELIN	G_DUR, G_BAR, "", BAR_W - 16 - TIME_W, ROW1_Y + 2, TIME_W, LABEL_H, 2, G_SECOND, AR_LEFT
	SLIDERIN	G_POS, G_BAR, S_act_seek_, 24 + TIME_W, ROW1_Y, BAR_W - 2 * (24 + TIME_W), 1, AR_WIDTH
	FONT	S_systemFontOfSize_weight_, 13, X_SEMIBOLD
	LABELIN	G_TITLE, G_BAR, "", 16, ROW2_C - 9, TEXT_W, 18, 0, G_TEXT, AR_WIDTH | AR_RIGHT
	FONT	S_systemFontOfSize_weight_, 12, X_REGULAR
	LABELIN	G_ARTIST, G_BAR, "", 16, ROW2_C - 17, TEXT_W, 16, 0, G_SECOND, AR_WIDTH | AR_RIGHT
	BTN	G_BACK, G_BAR, "gobackward.10", "Back 10 seconds", S_act_back_, "Back 10 seconds (\342\214\230\342\206\220)", BACK_X, ROW2_C - BTN_S / 2, BTN_S, 16, AR_LEFT | AR_RIGHT, G_TEXT
	BTN	G_PP, G_BAR, "play.fill", "Play or pause", S_act_toggle_, "Play or pause (Space)", PLAY_X, ROW2_C - PLAY_S / 2, PLAY_S, 17, AR_LEFT | AR_RIGHT, G_BGC
	LAYERBG	G_YEL, PLAY_S / 2
	BTN	G_FWD, G_BAR, "goforward.10", "Forward 10 seconds", S_act_fwd_, "Forward 10 seconds (\342\214\230\342\206\222)", FWD_X, ROW2_C - BTN_S / 2, BTN_S, 16, AR_LEFT | AR_RIGHT, G_TEXT
	BTN	G_AOBTN, G_BAR, "headphones", "Audio only", S_act_aonly_, "Audio Only (\342\214\245\342\214\230A)", AO_X, ROW2_C - ICON_S / 2, ICON_S, 13, AR_LEFT, G_SECOND
	BTN	G_MUTE, G_BAR, "speaker.wave.2.fill", "Mute", S_act_mute_, "Mute (\342\214\245\342\214\230\342\206\223)", MUTE_X, ROW2_C - ICON_S / 2, ICON_S, 13, AR_LEFT, G_SECOND
	SLIDERIN	G_VOL, G_BAR, S_act_vol_, VOL_X, ROW2_C - SLIDER_H / 2, VOL_W, 100, AR_LEFT

	; AirPlay: This Mac's picture and sound to an Apple TV or an AirPlay TV or speaker; lit while it does.
	CLS	AVRoutePickerView
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=N"
	RN	AIR_X, ROW2_C - AIR_W / 2, AIR_W, AIR_W
	MSG	S_setPlayer_, "O"
	.byte	G_PLAYER >> 3
	MSG	S_setDelegate_, "O"           ; air_prepare as it opens
	.byte	G_CTRL >> 3
	MSG	S_setRoutePickerButtonBordered_, "I"
	.byte	0
	MSG	S_setRoutePickerButtonColor_forState_, "OI"
	.byte	G_SECOND >> 3, 0          ; normal
	MSG	S_setRoutePickerButtonColor_forState_, "OI"
	.byte	G_YEL >> 3, 2             ; active
	MSG	S_setToolTip_, "S"
	.asciz	"AirPlay"
	MASKV	AR_LEFT
	ADDIN	G_BAR

	; Open from URL: a field floating in the middle of the stage (placed by layout_stage).
	NEWV	NSView, 0, 0, URL_W, URL_H
	STO	G_URLBOX
	LAYERBG	G_SURF2, 12
	MSG	S_setHidden_, "I"
	.byte	1
	IMG	G_T1, "link", "Link"
	CLS	NSImageView
	MSG	S_imageViewWithImage_, "=O"
	.byte	G_T1 >> 3
	MSG	S_setFrame_, "N"
	RN	16, 14, 20, 20
	MSG	S_setContentTintColor_, "O"
	.byte	G_SECOND >> 3
	ADDIN	G_URLBOX
	FONT	S_systemFontOfSize_weight_, 17, X_REGULAR
	CLS	NSTextField
	MSG	S_alloc, "="
	MSG	S_initWithFrame_, "=N"
	RN	46, 12, URL_W - 62, 24
	STO	G_FIELD
	MSG	S_setBezeled_, "I"
	.byte	0
	MSG	S_setDrawsBackground_, "I"
	.byte	0
	MSG	S_setFocusRingType_, "I"
	.byte	1                         ; none: the caret shows focus
	MSG	S_setFont_, "O"
	.byte	G_T0 >> 3
	MSG	S_setTextColor_, "O"
	.byte	G_TEXT >> 3
	MSG	S_setPlaceholderString_, "S"
	.asciz	"Link or search"
	MSG	S_setTarget_, "O"
	.byte	G_CTRL >> 3
	MSG	S_setAction_, "Y"
	.byte	(S_act_play_ - B_ACT) >> 3
	MSG	S_setDelegate_, "O"       ; Escape closes it
	.byte	G_CTRL >> 3
	ADDIN	G_URLBOX
	MSG	S_cell, "="
	MSG	S_setScrollable_, "I"     ; one line that scrolls, however long the link
	.byte	1
	MSG	S_setUsesSingleLineMode_, "I"
	.byte	1

	; Images swapped by ui_refresh.
	IMAGE	G_IMGPLAY, "play.fill", "Play"
	IMAGE	G_IMGPAUSE, "pause.fill", "Pause"
	IMAGE	G_IMGMUTED, "speaker.slash.fill", "Unmute"
	IMAGE	G_IMGUNMUTED, "speaker.wave.2.fill", "Mute"
	LD	G_CONTENT                 ; then to the window's first size, as the views grow with it
	MSG	S_setFrameSize_, "DD"
	.short	START_W * 4, START_H * 4
	OP_END

; The first size, centered; neither is saved, so the app writes no preferences. The window is drawn and sent at once: its stage comes after.
Lprog_show:
	LD	G_WIN
	MSG	S_setContentSize_, "DD"
	.short	START_W * 4, START_H * 4
	MSG	S_center
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	MSG	S_makeFirstResponder_, "O"
	.byte	G_CONTENT >> 3
	LD	G_WIN
	MSG	S_displayIfNeeded
	CLS	CATransaction
	MSG	S_flush
	OP_END

; The engine's layer into its view, laid out by pic_layout.
Lprog_attach:
	LD	G_SBV
	MSG	S_setWantsLayer_, "I"
	.byte	1
	MSG	S_layer, "="
	MSG	S_addSublayer_, "O"
	.byte	G_SBLAYER >> 3
	OP_END



; Open from URL: the window forward, the field shown and focused with its text selected.
Lprog_focus:
	LD	G_URLBOX
	MSG	S_setHidden_, "I"
	.byte	0
	LD	G_WIN
	MSG	S_makeKeyAndOrderFront_, "I"
	.byte	0
	LD	G_FIELD
	MSG	S_selectText_, "I"
	.byte	0
	OP_END

; The 1 Hz poll timer (macOS may coalesce its wakeups), then the run loop.
Lprog_run:
	CLS	NSTimer
	MSG	S_scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_, "=DOYII"
	.short	4
	.byte	G_CTRL >> 3, (S_act_tick_ - B_ACT) >> 3, 0, 1
	MSG	S_setTolerance_, "D"
	.short	1
	LD	G_APP
	MSG	S_activate
	MSG	S_run
	OP_END

; InnerTube endpoints: URL, then the field mask (it cuts a player response from ~183 KB to ~69 KB).
Lep_guide:	.asciz	"https://www.youtube.com/youtubei/v1/guide?prettyPrint=false", "X-Goog-FieldMask", "responseContext.visitorData", ""
Lep_search:	.asciz	"https://www.youtube.com/youtubei/v1/search?prettyPrint=false", "X-Goog-FieldMask", "contents,responseContext.visitorData", ""
Lep_player:	.asciz	"https://www.youtube.com/youtubei/v1/player?prettyPrint=false", "X-Goog-FieldMask", "streamingData,videoDetails,playabilityStatus,responseContext.visitorData", ""

; Headers of every InnerTube request.
Lapi_headers:
	.asciz	"Content-Type", "application/json"
	.asciz	"Origin", "https://www.youtube.com"
	.asciz	"Accept-Language", "en-US,en;q=0.9"
	.byte	0

; InnerTube clients: User-Agent, name, version, OS and its version, other context fields, the name's number. The player chain is tried in order: VISIONOS URLs serve whole streams, the rest cover what it refuses.
Lclients:
	.short	Lcl2 - Lclients
	.asciz	"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
	.asciz	"VISIONOS", "1.02", "visionOS", "26.5.23O471"
	.asciz	"\"deviceModel\":\"RealityDevice17,1\",\"deviceMake\":\"Apple\",", "101"
Lcl2:
	.short	Lcl3 - Lcl2
	.asciz	"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; en_US) gzip"
	.asciz	"ANDROID_VR", "1.65.10", "Android", "12L"
	.asciz	"\"deviceModel\":\"Quest 3\",\"androidSdkVersion\":32,", "28"
Lcl3:
	.short	Lcl4 - Lcl3
Lc_android:	                          ; also the search client
	.asciz	"com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US) gzip"
	.asciz	"ANDROID", "20.10.38", "Android", "14"
	.asciz	"\"androidSdkVersion\":34,", "3"
Lcl4:
	.short	Lcl5 - Lcl4
	.asciz	"com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X; en_US)"
	.asciz	"IOS", "20.10.4", "iOS", "18.3.2.22D82"
	.asciz	"\"deviceModel\":\"iPhone16,2\",", "5"
Lcl5:
	.short	0
Lc_web:	                                  ; the visitorData client
	.asciz	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
	.asciz	"WEB", "2.20260114.08.00", "Windows", "10.0"
	.asciz	"", "1"

; WORDS m, p — the words of the registry's names, most used first: byte 0x80 + n in a name or a word stands for word n.
.macro WORDS m, p
	\m	\p, set
	\m	\p, NS
	\m	\p, With
	\m	\p, in
	\m	\p, CM
	\m	\p, ing, in, g
	\m	\p, str
	\m	\p, act_
	\m	\p, ent
	\m	\p, URL
	\m	\p, ack
	\m	\p, ation, a, tion
	\m	\p, is
	\m	\p, In
	\m	\p, lay
	\m	\p, ed:
	\m	\p, tion
	\m	\p, SampleBuffer, Sa, mple, Buffer
	\m	\p, String, Str, ing
	\m	\p, loc
	\m	\p, ter
	\m	\p, Content, C, ont, ent
	\m	\p, Data
	\m	\p, For
	\m	\p, Get
	\m	\p, Value
	\m	\p, der
	\m	\p, dispatch_, d, is, patch_
	\m	\p, Item
	\m	\p, Media
	\m	\p, Time, T, ime
	\m	\p, ate
	\m	\p, ction, c, tion
	\m	\p, ele
	\m	\p, ont
	\m	\p, Image
	\m	\p, Layer
	\m	\p, Picture
	\m	\p, ame
	\m	\p, ate:, ate, :
	\m	\p, for
	\m	\p, per
	\m	\p, res
	\m	\p, ueue
	\m	\p, add
	\m	\p, ance
	\m	\p, ize
	\m	\p, olor
	\m	\p, ound
	\m	\p, tor
	\m	\p, Buffer
	\m	\p, Create, Cre, ate
	\m	\p, Set
	\m	\p, Size:, S, ize, :
	\m	\p, Type
	\m	\p, View
	\m	\p, able
	\m	\p, ask
	\m	\p, enu
	\m	\p, er:
	\m	\p, initWith, in, it, With
	\m	\p, ode
	\m	\p, Audio
	\m	\p, Block, B, loc, k
	\m	\p, Description, Descrip, tion
	\m	\p, InPictureController, In, Picture, C, ontrol, ler
	\m	\p, Player, P, lay, er
	\m	\p, Session, Ses, sion
	\m	\p, ime
	\m	\p, lass
	\m	\p, mple
	\m	\p, objc_
	\m	\p, rea
	\m	\p, tes
	\m	\p, use
	\m	\p, val
	\m	\p, AudioFileStream, Audio, FileSt, rea, m
	\m	\p, Display, D, is, p, lay
	\m	\p, FormatDescription, For, mat, Description
	\m	\p, Object
	\m	\p, Ready
	\m	\p, Title
	\m	\p, equest
	\m	\p, picture
	\m	\p, pplication, pplic, ation
	\m	\p, sion
	\m	\p, Array
	\m	\p, Configuration, Configur, ation
	\m	\p, HTTP
	\m	\p, Render, Ren, der
	\m	\p, Text
	\m	\p, Trans
	\m	\p, Window, W, in, dow
	\m	\p, arget:
	\m	\p, cale
	\m	\p, ctiv
	\m	\p, current, curr, ent
	\m	\p, data
	\m	\p, elease, ele, ase
	\m	\p, ity:
	\m	\p, open
	\m	\p, ppear
	\m	\p, select, s, ele, ct
	\m	\p, stop
	\m	\p, Attachment, Attachm, ent
	\m	\p, Button
	\m	\p, CMVideo, CM, Video
	\m	\p, Character, Charac, ter
	\m	\p, FormatDescriptionCreateFrom, FormatDescription, Create, From
	\m	\p, Hidden
	\m	\p, Interval:, In, ter, val, :
	\m	\p, RoutePicker
	\m	\p, Symbol
	\m	\p, length
	\m	\p, ontrol, ont, rol
	\m	\p, semaphore_
	\m	\p, weight:
	\m	\p, Flavor_ISOFamily
	\m	\p, NSFontWeight, NS, F, ont, Weight
	\m	\p, SelectionGroup, S, ele, ction, Group
	\m	\p, register, reg, is, ter
	\m	\p, FirstResponder, FirstRespon, der
	\m	\p, HTTPHeaderField:, HTTP, Hea, der, Field:
	\m	\p, VTDecompression, VTDecomp, res, sion
	\m	\p, completionHandler:, co, mple, tion, Handl, er:
	\m	\p, kCMSampleAttachmentKey_, k, CM, Sa, mple, Attachment, Key_
	\m	\p, os_unfair_lock_, os_unfair_, loc, k_
	\m	\p, queue_attr_make_with_, q, ueue, _attr_make_with_
.endm
.macro WMATCH p, w, parts:vararg
	.ifc	\p, _\w
	.byte	Lwn
	.set	Lwf, 1
	.endif
	.set	Lwn, Lwn + 1
.endm
.macro WEMIT p, w, a, b, c, d, e, f, g, h ; a word, whole or in words of its own that spell it
	.ifb	\a
	.asciz	"\w"
	.else
	.ifnc	\w, \a\b\c\d\e\f\g\h
	.error	"the pieces do not spell the word"
	.endif
	NAME	\a, \b, \c, \d, \e, \f, \g, \h
	.endif
.endm
.macro NAME parts:vararg                   ; each piece a word's byte, else as it is
	.irp	p, \parts
	.ifnb	\p
	.set	Lwn, 0x80
	.set	Lwf, 0
	WORDS	WMATCH, _\p
	.if	Lwf == 0
	.ascii	"\p"
	.endif
	.endif
	.endr
	.byte	0
.endm
Lreg_words:
	WORDS	WEMIT

; The registry's names, in its order.
.macro REG sym, parts:vararg
	NAME	\parts
.endm
.macro REGSEL
.endm
.macro REGCLS
.endm
.macro REGACT
.endm
.macro FN name, a, b, c, d, e, f, g, h, i, j, k, l, m
	SPELL	F_\name, \name, \a, \b, \c, \d, \e, \f, \g, \h, \i, \j, \k, \l, \m
.endm
Lreg_names:
	REGISTRY
	.byte	0
Ls_avkit:	.asciz	"/System/Library/Frameworks/AVKit.framework/AVKit"
Ls_calloc:	.asciz	"calloc"
Ls_dlopen:	.asciz	"dlopen"
	.p2align 3
Ldl:	.quad	_dlsym, 0, 0              ; then G and B, for callbacks

