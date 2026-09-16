BeforeAll { Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force }

Describe 'Semantic topology comparison' {
    It 'ignores evidence-key churn when topology semantics are unchanged' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='owns';Qualifier='';State=@{};EvidenceKeys=@('evidence:old')})}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='owns';Qualifier='';State=@{};EvidenceKeys=@('evidence:new')})}
        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'reports edge state changes without requiring edge identity churn' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='assignedDirectoryRole';Qualifier='/';State=@{assignmentType='active'};EvidenceKeys=@()})}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Signals=@();Edges=@([pscustomobject]@{Key='edge:x';From='a';To='b';Relationship='assignedDirectoryRole';Qualifier='/';State=@{assignmentType='eligible'};EvidenceKeys=@()})}
        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 1
    }

    It 'ignores nested property-order churn from Graph and JSON round-trips' {
        $a=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:x';Id='x';TenantId='t';Kind='directoryRole';DisplayName='Role';
            Properties=[pscustomobject][ordered]@{description='same';isEnabled=$true;inheritsPermissionsFrom=@([pscustomobject][ordered]@{id='base'})}
        })}
        $b=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:x';Id='x';TenantId='t';Kind='directoryRole';DisplayName='Role';
            Properties=[pscustomobject][ordered]@{inheritsPermissionsFrom=@([pscustomobject][ordered]@{id='base'});isEnabled=$true;description='same'}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'normalizes equivalent ISO-8601 fractional-second precision in signal state' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='same';
            State=[ordered]@{endDateTime='2026-11-03T09:51:20Z';daysRemaining=48}
        })}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='same';
            State=[ordered]@{daysRemaining=48;endDateTime='2026-11-03T09:51:20.0000000Z'}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'ignores volatile credential countdown and countdown-reason changes' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='The certificate expires in 48 day(s).';
            State=[ordered]@{endDateTime='2026-11-03T09:51:20Z';credentialType='keyCredential';expiryWindow='60 days';daysRemaining=48}
        })}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='The certificate expires in 47 day(s).';
            State=[ordered]@{daysRemaining=47;expiryWindow='60 days';credentialType='keyCredential';endDateTime='2026-11-03T09:51:20.0000000Z'}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'ignores volatile expired-credential countdown changes' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpired';Severity='High';Reason='The client secret expired 1 day(s) ago.';
            State=[ordered]@{endDateTime='2026-09-15T09:51:20Z';credentialType='passwordCredential';expiryWindow='Expired';daysRemaining=-1}
        })}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpired';Severity='High';Reason='The client secret expired 2 day(s) ago.';
            State=[ordered]@{daysRemaining=-2;expiryWindow='Expired';credentialType='passwordCredential';endDateTime='2026-09-15T09:51:20.0000000Z'}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'still reports a real credential expiry timestamp change' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='The certificate expires in 48 day(s).';
            State=[ordered]@{endDateTime='2026-11-03T09:51:20Z';credentialType='keyCredential';expiryWindow='60 days';daysRemaining=48}
        })}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='The certificate expires in 48 day(s).';
            State=[ordered]@{endDateTime='2026-11-04T09:51:20Z';credentialType='keyCredential';expiryWindow='60 days';daysRemaining=48}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 1
    }

    It 'still reports credential expiry-window and severity transitions' {
        $a=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Low';Reason='The client secret expires in 31 day(s).';
            State=[ordered]@{endDateTime='2026-10-17T09:51:20Z';credentialType='passwordCredential';expiryWindow='60 days';daysRemaining=31}
        })}
        $b=[pscustomobject]@{TenantId='t';Nodes=@();Edges=@();Signals=@([pscustomobject]@{
            Key='signal:x';TargetKey='node:x';Type='credentialExpiring';Severity='Medium';Reason='The client secret expires in 30 day(s).';
            State=[ordered]@{endDateTime='2026-10-17T09:51:20Z';credentialType='passwordCredential';expiryWindow='30 days';daysRemaining=30}
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 1
    }

    It 'ignores semantic collection-order churn in node properties' {
        $a=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:app';Id='app';TenantId='t';Kind='application';DisplayName='App';
            Properties=[pscustomobject]@{
                requiredResourceAccess=@(
                    [pscustomobject]@{resourceAppId='graph';resourceAccess=@(
                        [pscustomobject]@{id='permission-b';type='Role'},
                        [pscustomobject]@{id='permission-a';type='Scope'}
                    )},
                    [pscustomobject]@{resourceAppId='exchange';resourceAccess=@(
                        [pscustomobject]@{id='permission-c';type='Role'}
                    )}
                )
            }
        })}
        $b=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:app';Id='app';TenantId='t';Kind='application';DisplayName='App';
            Properties=[pscustomobject]@{
                requiredResourceAccess=@(
                    [pscustomobject]@{resourceAppId='exchange';resourceAccess=@(
                        [pscustomobject]@{type='Role';id='permission-c'}
                    )},
                    [pscustomobject]@{resourceAccess=@(
                        [pscustomobject]@{type='Scope';id='permission-a'},
                        [pscustomobject]@{type='Role';id='permission-b'}
                    );resourceAppId='graph'}
                )
            }
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

    It 'ignores live-shaped application credential property order and timestamp precision churn' {
        $a=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:credential';Id='app:keyCredential:key';TenantId='t';Kind='applicationCredential';DisplayName='CN=Monitor';
            Properties=[pscustomobject][ordered]@{
                usage='Verify';credentialType='keyCredential';keyId='key';parentKind='application';
                endDateTime='2028-09-15T16:15:25Z';parentId='app';type='AsymmetricX509Cert';
                startDateTime='2026-09-15T16:15:25Z';customKeyIdentifier='abc'
            }
        })}
        $b=[pscustomobject]@{TenantId='t';Edges=@();Signals=@();Nodes=@([pscustomobject]@{
            Key='node:credential';Id='app:keyCredential:key';TenantId='t';Kind='applicationCredential';DisplayName='CN=Monitor';
            Properties=[pscustomobject][ordered]@{
                parentId='app';customKeyIdentifier='abc';startDateTime='2026-09-15T16:15:25.0000000Z';
                credentialType='keyCredential';type='AsymmetricX509Cert';usage='Verify';keyId='key';parentKind='application';
                endDateTime='2028-09-15T16:15:25.0000000Z'
            }
        })}

        $result=Compare-EntraTopologyGraph -ReferenceGraph $a -DifferenceGraph $b
        $result.Summary.Changed | Should -Be 0
    }

}
