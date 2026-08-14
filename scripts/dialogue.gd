class_name Dialogue
extends RefCounted
## Every line in the game. Short list on purpose, most of the story is doors
## and light, not talking.
##
## NOTE: the Arabic below is a first draft. It should be reviewed by a native
## speaker before submission; the English is the reference meaning.

enum Style {
	DAD,  ## Labelled, upright. The only voice with a name attached.
	KID,  ## Unlabelled, italic, dimmer. The player's own thoughts.
}

## Speaker labels are keyed off Style so the attribution can never be typed
## inconsistently at a call site.
const SPEAKERS := {
	Style.DAD: {"ar": "أبي", "en": "DAD"},
	Style.KID: {"ar": "", "en": ""},
}

# The reassurance is stored once and referenced twice on purpose. See the two
# entries that use it below.
const _REASSURE_AR := "ما فيه شي داخل. نام."
const _REASSURE_EN := "There's nothing in there. Go to sleep."

const LINES := {
	# --- Act 0: bedtime ----------------------------------------------------
	"dad_bedtime": {
		"ar": "يلا يا بطل، وقت النوم.",
		"en": "Come on, champ. Bedtime.",
		"style": Style.DAD,
	},
	# The only objective-setting line of the act. Names the bathroom so the
	# lit door across the landing needs no marker.
	"kid_need_toy": {
		"ar": "ما أقدر أنام بدونه... خليته في الحمام.",
		"en": "I can't sleep without him... I left him in the bathroom.",
		"style": Style.KID,
	},
	"kid_got_toy": {
		"ar": "حصلتك.",
		"en": "Found you.",
		"style": Style.KID,
	},
	# Goodnight ritual. Also sets up the empty hiding spot in 2.2.
	"kid_goodnight_toy": {
		"ar": "تصبح على خير.",
		"en": "Good night.",
		"style": Style.KID,
	},
	# The closet, any time the player tries it themselves.
	"kid_no_way": {
		"ar": "لا... ما راح أفتحه.",
		"en": "No... I'm not opening it.",
		"style": Style.KID,
	},

	# --- Act 1: the closet -------------------------------------------------
	"kid_call": {
		"ar": "بابا!",
		"en": "Dad!",
		"style": Style.KID,
	},
	"dad_answer": {
		"ar": "نعم؟",
		"en": "Yes?",
		"style": Style.DAD,
	},
	"kid_closet": {
		"ar": "فيه شي في الدولاب",
		"en": "There's something in the closet",
		"style": Style.KID,
	},
	# Said through the door, while the kid is under the covers and cannot see
	# him. This is the line the whole ending is built on.
	"dad_reassure": {
		"ar": _REASSURE_AR,
		"en": _REASSURE_EN,
		"style": Style.DAD,
	},
	"dad_quiet": {
		"ar": "وما أبي أسمع صوت.",
		"en": "And I don't want to hear a sound.",
		"style": Style.DAD,
	},

	# --- Act 2.2: the empty hiding spot ------------------------------------
	# The only line that sets an objective. Everything else the player infers.
	"kid_where": {
		"ar": "...وين؟",
		"en": "...where is it?",
		"style": Style.KID,
	},

	# --- Act 3: the bathroom door ------------------------------------------
	# Same constants as `dad_reassure` on purpose so the two lines can never
	# drift apart in editing. The label still saying DAD at the bathroom door
	# is the whole point of the ending.
	"dad_reassure_again": {
		"ar": _REASSURE_AR,
		"en": _REASSURE_EN,
		"style": Style.DAD,
	},
}


static func has_line(id: String) -> bool:
	return LINES.has(id)


static func get_text(id: String, lang: String) -> String:
	if not LINES.has(id):
		push_warning("Dialogue: unknown line id '%s'" % id)
		return ""
	return LINES[id].get(lang, "")


static func get_style(id: String) -> Style:
	if not LINES.has(id):
		return Style.KID
	return LINES[id]["style"]


static func get_speaker(id: String, lang: String) -> String:
	return SPEAKERS[get_style(id)].get(lang, "")
