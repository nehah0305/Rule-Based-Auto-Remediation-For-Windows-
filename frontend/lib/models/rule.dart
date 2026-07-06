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
  final bool active;
  final int hitCount;
  final String? lastHit;
  final String? rollbackScript;
  final int verificationTimeoutSec;

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
    this.active = true,
    this.hitCount = 0,
    this.lastHit,
    this.rollbackScript,
    this.verificationTimeoutSec = 60,
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
    active:             (j['active'] as int? ?? 1) == 1,
    hitCount:           (j['hit_count'] as num?)?.toInt() ?? 0,
    lastHit:            j['last_hit'] as String?,
    rollbackScript:     j['rollback_script'] as String?,
    verificationTimeoutSec: (j['verification_timeout_sec'] as num?)?.toInt() ?? 60,
  );

  Rule copyWith({bool? active}) => Rule(
    id: id, name: name, eventId: eventId, source: source,
    messageRegex: messageRegex, remediationScript: remediationScript,
    autoRemediate: autoRemediate, category: category, severity: severity,
    description: description, recommendedAction: recommendedAction,
    scriptType: scriptType, priority: priority, cooldownMinutes: cooldownMinutes,
    stopProcessing: stopProcessing,
    active: active ?? this.active,
    hitCount: hitCount, lastHit: lastHit,
    rollbackScript: rollbackScript, verificationTimeoutSec: verificationTimeoutSec,
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
    'rollback_script':     rollbackScript,
    'verification_timeout_sec': verificationTimeoutSec,
  };
}
