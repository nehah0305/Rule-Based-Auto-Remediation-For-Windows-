class Rule {
  final int id;
  final String name;
  final int? eventId;
  final String? source;
  final String? messageRegex;
  final String? remediationScript;
  final bool autoRemediate;
  final String? category;
  final String? severity;
  final String? description;
  final String? recommendedAction;
  final String scriptType;
  final int priority;
  final int cooldownMinutes;
  final bool stopProcessing;

  Rule({
    required this.id,
    required this.name,
    this.eventId,
    this.source,
    this.messageRegex,
    this.remediationScript,
    this.autoRemediate = false,
    this.category,
    this.severity,
    this.description,
    this.recommendedAction,
    this.scriptType = 'file',
    this.priority = 100,
    this.cooldownMinutes = 0,
    this.stopProcessing = false,
  });

  factory Rule.fromJson(Map<String, dynamic> j) => Rule(
    id:                 j['id'] as int,
    name:               j['name'] as String? ?? '',
    eventId:            j['event_id'] as int?,
    source:             j['source'] as String?,
    messageRegex:       j['message_regex'] as String?,
    remediationScript:  j['remediation_script'] as String?,
    autoRemediate:      j['auto_remediate'] as bool? ?? false,
    category:           j['category'] as String?,
    severity:           j['severity'] as String?,
    description:        j['description'] as String?,
    recommendedAction:  j['recommended_action'] as String?,
    scriptType:         j['script_type'] as String? ?? 'file',
    priority:           (j['priority'] as num?)?.toInt() ?? 100,
    cooldownMinutes:    (j['cooldown_minutes'] as num?)?.toInt() ?? 0,
    stopProcessing:     j['stop_processing'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'name':                name,
    'event_id':            eventId,
    'source':              source,
    'message_regex':       messageRegex,
    'remediation_script':  remediationScript,
    'auto_remediate':      autoRemediate,
    'category':            category,
    'severity':            severity,
    'description':         description,
    'recommended_action':  recommendedAction,
    'script_type':         scriptType,
    'priority':            priority,
    'cooldown_minutes':    cooldownMinutes,
    'stop_processing':     stopProcessing,
  };
}
