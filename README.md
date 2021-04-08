## F5 Nginx Blue-Green Canary Deployments with JFrog

Learn how you can build and deploy your application utilizing blue and green canary deployments with JFrog and F5 Nginx Ingress Controllers on AWS EKS.

![F5 (3)](https://user-images.githubusercontent.com/6440106/113944905-25dec600-97ba-11eb-9a8e-7e5aeb16abfb.png)

## The Pipeline
JFrog Pipelines CI/CD orchestrates the building and deployment of our demo app. The CI/CD pipeline is defined in the [pipeline.yml](./pipeline.yml).

1. Docker Build (docker_build) - This step builds a docker image using the [Dockerfile](./demo-app/Dockerfile).
2. Docker Push (docker_push) - This step publishes the docker image to the demo-docker-local repository.
3. Promote (docker_promote) - This step promotes the docker image to demo-docker-prod-local (usually after a validation step).
4. Deploy (eks_deploy) - Deploy the newly built image to an EKS cluster using [deployment.yml](./demo-app/deployment.yml).

![F5 - Page 2](https://user-images.githubusercontent.com/6440106/114054463-beba2380-9844-11eb-96bf-3b4a8bbe5927.png)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.

