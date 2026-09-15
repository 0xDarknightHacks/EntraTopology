Import-Module (Join-Path $PSScriptRoot '..' 'EntraTopology.psd1') -Force

Describe 'Graph batch transport' {
    InModuleScope EntraTopology {
        BeforeEach {
            Mock Assert-EntraTopologyGraphConnected { [pscustomobject]@{ TenantId='tenant' } }
            Mock Start-Sleep {}
        }

        It 'parses dictionary-shaped batch responses and correlates the original request' {
            Mock Invoke-MgGraphRequest {
                @{
                    responses = @(
                        @{ id='1'; status=200; body=@{ value=@(@{ id='u1'; displayName='User One' }) } }
                    )
                }
            }
            $request=[pscustomobject]@{Uri='/groups/g1/members';GroupId='g1'}
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @($request))
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'Success'
            $result[0].Request.GroupId | Should -Be 'g1'
            $result[0].Items.Count | Should -Be 1
            $result[0].Items[0].id | Should -Be 'u1'
        }

        It 'follows per-subrequest pagination and returns one aggregated result' {
            $script:batchPage=0
            Mock Invoke-MgGraphRequest {
                $script:batchPage++
                if($script:batchPage -eq 1){
                    return [pscustomobject]@{responses=@([pscustomobject]@{
                        id='1';status=200;headers=@{};body=@{
                            value=@([pscustomobject]@{id='u1'});
                            '@odata.nextLink'='https://graph.microsoft.com/v1.0/groups/g1/members?$skiptoken=next'
                        }
                    })}
                }
                [pscustomobject]@{responses=@([pscustomobject]@{id='1';status=200;headers=@{};body=@{value=@([pscustomobject]@{id='u2'})}})}
            }
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @([pscustomobject]@{Uri='/groups/g1/members'}))
            $result[0].Status | Should -Be 'Success'
            $result[0].PageCount | Should -Be 2
            @($result[0].Items).Count | Should -Be 2
            @($result[0].Items.id) | Should -Contain 'u1'
            @($result[0].Items.id) | Should -Contain 'u2'
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'treats an empty value collection as zero items rather than a body object' {
            Mock Invoke-MgGraphRequest {
                [pscustomobject]@{responses=@([pscustomobject]@{id='1';status=200;headers=@{};body=@{value=@()}})}
            }
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @([pscustomobject]@{Uri='/groups/g1/owners'}))
            $result[0].Status | Should -Be 'Success'
            @($result[0].Items).Count | Should -Be 0
        }

        It 'retries a throttled subrequest using Retry-After' {
            $script:batchAttempt=0
            Mock Invoke-MgGraphRequest {
                $script:batchAttempt++
                if($script:batchAttempt -eq 1){
                    return [pscustomobject]@{responses=@([pscustomobject]@{
                        id='1';status=429;headers=@{'Retry-After'='0';'request-id'='req-429'};
                        body=@{error=@{code='TooManyRequests';message='Slow down'}}
                    })}
                }
                [pscustomobject]@{responses=@([pscustomobject]@{id='1';status=200;headers=@{};body=@{value=@([pscustomobject]@{id='u1'})}})}
            }
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @([pscustomobject]@{Uri='/users'}))
            $result[0].Status | Should -Be 'Success'
            $result[0].RetryCount | Should -Be 1
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'retries transient 5xx subrequest failures' {
            $script:batchAttempt=0
            Mock Invoke-MgGraphRequest {
                $script:batchAttempt++
                if($script:batchAttempt -eq 1){
                    return [pscustomobject]@{responses=@([pscustomobject]@{
                        id='1';status=503;headers=@{'Retry-After'='0'};
                        body=@{error=@{code='ServiceUnavailable';message='Temporary failure'}}
                    })}
                }
                [pscustomobject]@{responses=@([pscustomobject]@{id='1';status=200;headers=@{};body=@{value=@()}})}
            }
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @([pscustomobject]@{Uri='/devices'}))
            $result[0].Status | Should -Be 'Success'
            $result[0].RetryCount | Should -Be 1
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }

        It 'preserves error provenance for a non-retriable subrequest failure' {
            Mock Invoke-MgGraphRequest {
                [pscustomobject]@{responses=@([pscustomobject]@{
                    id='1';status=403;headers=@{'request-id'='req-403'};
                    body=@{error=@{code='Authorization_RequestDenied';message='Insufficient privileges'}}
                })}
            }
            $result=@(Invoke-EntraTopologyGraphBatch -Requests @([pscustomobject]@{Uri='/groups/g1/owners'}))
            $result[0].Status | Should -Be 'InsufficientPermission'
            $result[0].StatusCode | Should -Be 403
            $result[0].ErrorCode | Should -Be 'Authorization_RequestDenied'
            $result[0].ErrorMessage | Should -Be 'Insufficient privileges'
            $result[0].RequestId | Should -Be 'req-403'
            $result[0].SourceEndpoint | Should -Be '/groups/g1/owners'
        }
    }
}
