# How FIPS build work


This diagram shows how the CI is setup:

Component versions are sourced from `hack/kubernetes-v<MAJOR>.<MINOR>` files.
If the file does not exist in the repo, build is skipped.

[Click here if the diagram does render correctly in github](https://mermaid.live/edit#pako:eNq9V91u2zYUfhVCA4YWs9JY_oktDAVcJ27TIKmRZL1Y4gtaOrKJSJRBUmncOO8woA-wq-0F9mJ7hFEk5VCyrLQ384UgHn7nnI-HH4_oRydIQ3B8Z8Hwaomu391SJH9XAjPx6uYqWEKYxRC-Occ0wzG6ZmSxADZ7jVz3LXoPFBgWcI4FIw83xRDpMfqYzn-dszdvJyCCJTobcMQgBsyBo4ilCXpPxIdsjkbTUw0jsQCG5mt0D4yTlKKfkcwf3CESIZLgBSB4IFzwmeaon2UOita7jMThZx2DP05Shk6wIWCsKh-hhuiTHa_k_BxOOhfGG2Www_HtUqeYcbD4w4NgOBAozcQqqzCvxlXJNncD7iaEpsy9t7jmVnu8whkHVxWlsG-QTI7jGGIVmD8WQ3SqaqetpbWWHUqLvZCqsFeqxjqSIvDvn3_8g-6yOTAKArhL5bwbkRVXs-OUCkwo9xUkEHFLvcQg9AsOE4ULNA5Y2EIso0ELjS9O0SrOFtJ51kzyA8SJIZi_Vrktpa2OUG5Hc0IxW7-Q4EQEoUmQv1YTSFGHdQlye0s95bpfSHEm114UWb7u1FfaaouaY79rDWcppbL-5J6IdZHIMu0ktOZcDkxKqzb_LqxW2Vo0tqwmMpilqsnp9Gq_qPzPJ5dXp58u6ijgFdGJWygXEUvl6pmbYCpjSRs3jeslXptx7igPqKye7jF8o2GjJOx3rzEzbEfnx_0ukmM0YsGS3AM3jL_9jU7MIVc7QorupqNp2gzytih7KsLGe2YxUvLdVqlIbAGU_JoASjyNAHvTG4HVflTbaWq8G3d-xJJSMS_P_69imsT7i7kLqBSzBlBfzBrgDxSz5G3FKKqsA_y2ilMcIpEWH89L_UXd5NXUkxC2b6zGXJwhnMdRJ-lAlu5g8VV_V5qAbpTFsUHbJS64_gAlr5ZSHue7KG2BNZT0017-855MJFq1l2rPySdKjefbX-g4_UL1UixpafmZe8tzk9Lh9rQqRXK2w8ur4dV4aupQZXnXIcr6rs1UEngtolbhFaSF385oSUwzvswFwWAh72tsvUETeZrNTjQ1eVW5SqcfyZ0yLV7eDHDx5SOmHfxS3q4vRCxRfhmRPskqpUD33LryL9E-tuPpy1S3LHNeU8XrE43XpVzPq1aZTmj4yghxLMnJ2xDMXmukyVjA7CBcrGPQF3IUkTj2f4J21IO2PStd9s5VLsgaFkVRF_o2bKdhmXidyItCG1i5aph4HehFvbp4WtMm2ABwtJtVaboRoTTdiFCabkbYmm5GGnVsSzUMujugbV82qAC6EOyiilbZiHo-PvtSWkrSkGAA_WBoQwoJ2fNOS_6vI6HjC5ZBy0mAJTgfOo-5560jlpDArePL1xCzu1vnlj5JnxWmv6dpUrixNFssHT_CMZejbBVKNR0TLP8xJlsrAxoCG6cZFY7fGXoqiOM_Og-O3-55B91er3d45B12B0f9bq_lrB3fbR92ugdeRxoOvaN23-t3nlrOV5XYOxgeHnV6neHgqDdsd9re03_di_2b)

```mermaid
graph TB
    Start([Scheduled/Manual Trigger]) --> GenerateMatrix[Generate Matrix Job<br/>Fetch K8s releases from GitHub API<br/>Filter by version & check if image exists]
    
    GenerateMatrix --> BuildVersions{For Each K8s Version<br/>in Matrix}
    
    BuildVersions --> BuildK8sVersions[Build K8s Versions Job<br/>Parse version & extract outputs]
    
    BuildK8sVersions --> |k8s-minor-version<br/>k8s-version<br/>pause-image-version| ParallelBuilds{Parallel Image Builds}
    
    ParallelBuilds --> BuildK8sNodes[Build K8s Nodes Image<br/>🐳 kubernetes-node-fips<br/>Contains: kubectl, kubelet, kubeadm<br/>containerd, runc, CNI plugins]
    ParallelBuilds --> BuildHelm[Build Helm Image<br/>🐳 helm-fips<br/>Contains: helm binary]
    ParallelBuilds --> BuildEtcd[Build Etcd Image<br/>🐳 etcd-fips<br/>Contains: etcd, etcdctl]
    ParallelBuilds --> BuildKine[Build Kine Image<br/>🐳 kine-fips<br/>Contains: kine binary]
    ParallelBuilds --> BuildKonnectivity[Build Konnectivity Image<br/>🐳 konnectivity-server-fips<br/>Contains: konnectivity-server]
    
    BuildK8sNodes --> BuildK8sFips[Build K8s FIPS Image<br/>🐳 kubernetes:VERSION-fips<br/>Contains: apiserver, controller-manager, scheduler]
    
    BuildK8sNodes --> |Collect all images| BuildAmd64Tar[Build AMD64 Tar Archives<br/>📦 Extract binaries from images<br/>Create tar archives]
    BuildHelm --> BuildAmd64Tar
    BuildEtcd --> BuildAmd64Tar
    BuildKine --> BuildAmd64Tar
    BuildKonnectivity --> BuildAmd64Tar
    BuildK8sVersions --> |pause-image-version| BuildAmd64Tar
    
    BuildK8sNodes --> BuildArm64Tar[Build ARM64 Tar Archives<br/>📦 Extract binaries from images<br/>Create tar archives]
    BuildHelm --> BuildArm64Tar
    BuildEtcd --> BuildArm64Tar
    BuildKine --> BuildArm64Tar
    BuildKonnectivity --> BuildArm64Tar
    BuildK8sVersions --> |pause-image-version| BuildArm64Tar
    
    BuildAmd64Tar --> |Upload to GitHub Release| TarUploaded1[kubernetes-VERSION-amd64-fips.tar.gz<br/>kubernetes-VERSION-amd64-fips-full.tar.gz]
    BuildArm64Tar --> |Upload to GitHub Release| TarUploaded2[kubernetes-VERSION-arm64-fips.tar.gz<br/>kubernetes-VERSION-arm64-fips-full.tar.gz]
    
    TarUploaded1 --> BuildFullImage[Build K8s FIPS Full Image<br/>📥 Download tar archives from release<br/>🐳 Build kubernetes:VERSION-fips-full]
    TarUploaded2 --> BuildFullImage
    BuildK8sNodes --> BuildFullImage
    BuildHelm --> BuildFullImage
    BuildEtcd --> BuildFullImage
    BuildKine --> BuildFullImage
    BuildKonnectivity --> BuildFullImage
    
    BuildFullImage --> |Push to registry| FinalImage[🐳 kubernetes:VERSION-fips-full<br/>Contains: All control plane binaries<br/>+ tar archives with node components]
    
    BuildK8sFips --> |Push to registry| CPImage[🐳 kubernetes:VERSION-fips<br/>Control Plane Only]
    
    FinalImage --> End([Build Complete])
    CPImage --> End
    
    style Start fill:#e1f5e1
    style End fill:#e1f5e1
    style GenerateMatrix fill:#fff4e6
    style BuildK8sVersions fill:#e3f2fd
    style ParallelBuilds fill:#f3e5f5
    style BuildK8sNodes fill:#e8eaf6
    style BuildHelm fill:#e8eaf6
    style BuildEtcd fill:#e8eaf6
    style BuildKine fill:#e8eaf6
    style BuildKonnectivity fill:#e8eaf6
    style BuildK8sFips fill:#fff9c4
    style BuildAmd64Tar fill:#fce4ec
    style BuildArm64Tar fill:#fce4ec
    style BuildFullImage fill:#fff9c4
    style FinalImage fill:#c8e6c9
    style CPImage fill:#c8e6c9
```