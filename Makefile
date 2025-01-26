# ======================================
#          引入 .env 并导出变量
# ======================================

# 1. 通过 include .env 将 .env 文件中的内容包含到 Makefile 环境中
include .env

# 2. 通过 sed 命令去除掉行尾注释 (# 开头) 和空白行等，然后只提取 key 并导出为环境变量
#    -n ：禁止默认输出
#    's/ *#.*$$//' ：将以 '#' 开头的注释去掉
#    '/./ s/=.*$$// p' ：对非空行，去掉 '=' 号及之后的内容，然后打印（即只保留 key）
#    最终用 $(eval export ...) 将其导出为 Makefile 环境变量
$(eval export $(shell sed -ne 's/ *#.*$$//; /./ s/=.*$$// p' .env))

# 3. 将当前目录下的 src 文件夹添加到 PYTHONPATH 中，
#    方便在后续 Python 命令中引用该目录下的包/模块
PYTHONPATH := $(shell pwd)/src


# ======================================
#          Python依赖安装相关
# ======================================

# install: 创建一个基于 Python3.11 的 Poetry 虚拟环境并安装所有必要的依赖
install: # Create a local Poetry virtual environment and install all required Python dependencies.
	poetry env use 3.11
	poetry install --without superlinked_rag


# ======================================
#          帮助信息输出
# ======================================

# help: 输出当前 Makefile 中所有目标(target)及其简要说明
help:
	@grep -E '^[a-zA-Z0-9 -]+:.*#' Makefile | sort | while read -r l; do \
		printf "\033[1;32m$$(echo $$l | cut -f 1 -d':')\033[00m:$$(echo $$l | cut -f 2- -d'#')\n"; \
	done


# ======================================
#       Docker 基础设施相关命令
# ======================================

# local-start: 构建并以后台方式启动 Docker 容器（docker-compose.yml）
local-start: # Build and start your local Docker infrastructure.
	docker compose -f docker-compose.yml up --build -d

# local-stop: 停止并移除所有由 docker-compose.yml 启动的容器
local-stop: # Stop your local Docker infrastructure.
	docker compose -f docker-compose.yml down --remove-orphans


# ======================================
#           数据爬取相关命令
# ======================================

# local-test-medium: 通过 Curl 请求本地部署的 AWS Lambda (Docker中)，
#                    模拟爬取 Medium 文章的操作
local-test-medium: # Make a call to your local AWS Lambda (hosted in Docker) to crawl a Medium article.
	curl -X POST "http://localhost:9010/2015-03-31/functions/function/invocations" \
	  	-d '{"user": "Paul Iusztin", "link": "https://medium.com/decodingml/an-end-to-end-framework-for-production-ready-llm-systems-by-building-your-llm-twin-2cc6bb01141f"}'

# local-test-github: 同理，模拟爬取 GitHub 仓库的操作
local-test-github: # Make a call to your local AWS Lambda (hosted in Docker) to crawl a Github repository.
	curl -X POST "http://localhost:9010/2015-03-31/functions/function/invocations" \
	  	-d '{"user": "Paul Iusztin", "link": "https://github.com/decodingml/llm-twin-course"}'

# local-ingest-data: 从 data/links.txt 中逐行读取链接，
#                    调用本地 AWS Lambda 进行爬取
local-ingest-data: # Ingest all links from data/links.txt by calling your local AWS Lambda hosted in Docker.
	while IFS= read -r link; do \
		echo "Processing: $$link"; \
		curl -X POST "http://localhost:9010/2015-03-31/functions/function/invocations" \
			-d "{\"user\": \"Paul Iusztin\", \"link\": \"$$link\"}"; \
		echo "\n"; \
		sleep 2; \
	done < data/links.txt


# ======================================
#         RAG (Retriever) 流程相关
# ======================================

# local-test-retriever: 在 Poetry 环境中执行 Python 模块，以测试 RAG 检索功能
local-test-retriever: # Test the RAG retriever using your Poetry env
	cd src/feature_pipeline && poetry run python -m retriever

# local-generate-instruct-dataset: 在 Poetry 环境中执行 Python 脚本，
#                                  生成训练所需的 instruct 数据集
local-generate-instruct-dataset: # Generate the fine-tuning instruct dataset using your Poetry env.
	cd src/feature_pipeline && poetry run python -m generate_dataset.generate


# ======================================
#     AWS SageMaker: 训练 & 推理相关
# ======================================

# download-instruct-dataset: 在 Poetry 环境中执行脚本，下载 Fine-tuning 所需数据集
download-instruct-dataset: # Download the fine-tuning instruct dataset using your Poetry env.
	cd src/training_pipeline && PYTHONPATH=$(PYTHONPATH) poetry run python download_dataset.py

# create-sagemaker-execution-role: 创建一个 AWS SageMaker 执行角色，
#                                  用于后续的训练和推理
create-sagemaker-execution-role: # Create an AWS SageMaker execution role you need for the training and inference pipelines.
	cd src && PYTHONPATH=$(PYTHONPATH) poetry run python -m core.aws.create_execution_role

# start-training-pipeline-dummy-mode: 在 AWS SageMaker 上启动训练管线（测试模式）
start-training-pipeline-dummy-mode: # Start the training pipeline in AWS SageMaker.
	cd src/training_pipeline && poetry run python run_on_sagemaker.py --is-dummy

# start-training-pipeline: 在 AWS SageMaker 上正式启动训练管线
start-training-pipeline: # Start the training pipeline in AWS SageMaker.
	cd src/training_pipeline && poetry run python run_on_sagemaker.py

# local-start-training-pipeline: 在本地 Poetry 环境中启动训练管线 (不走云端)
local-start-training-pipeline: # Start the training pipeline in your Poetry env.
	cd src/training_pipeline && poetry run python -m finetune

# deploy-inference-pipeline: 将推理管线部署到 AWS SageMaker 上
deploy-inference-pipeline: # Deploy the inference pipeline to AWS SageMaker.
	cd src/inference_pipeline && poetry run python -m aws.deploy_sagemaker_endpoint

# call-inference-pipeline: 在 Poetry 环境中调用推理管线 client
call-inference-pipeline: # Call the inference pipeline client using your Poetry env.
	cd src/inference_pipeline && poetry run python -m main

# delete-inference-pipeline-deployment: 删除已部署到 AWS SageMaker 的推理端点
delete-inference-pipeline-deployment: # Delete the deployment of the AWS SageMaker inference pipeline.
	cd src/inference_pipeline && PYTHONPATH=$(PYTHONPATH) poetry run python -m aws.delete_sagemaker_endpoint

# local-start-ui: 在本地 Poery 环境中启动 Gradio UI，用于与模型交互
local-start-ui: # Start the Gradio UI for chatting with your LLM Twin using your Poetry env.
	cd src/inference_pipeline && poetry run python -m ui

# evaluate-llm: 在本地 Poetry 环境中执行 Python 脚本，对 LLM 模型做性能评测
evaluate-llm: # Run evaluation tests on the LLM model's performance using your Poetry env.
	cd src/inference_pipeline && poetry run python -m evaluation.evaluate

# evaluate-rag: 在本地 Poetry 环境中执行 Python 脚本，对 RAG 系统做性能评测
evaluate-rag: # Run evaluation tests specifically on the RAG system's performance using your Poetry env.
	cd src/inference_pipeline && poetry run python -m evaluation.evaluate_rag

# evaluate-llm-monitoring: 在本地 Poetry 环境中执行 Python 脚本，对 LLM 系统的监控指标进行评测
evaluate-llm-monitoring: # Run evaluation tests for monitoring the LLM system using your Poetry env.
	cd src/inference_pipeline && poetry run python -m evaluation.evaluate_monitoring


# ======================================
#       Superlinked 拓展系列相关
# ======================================

# install-superlinked: 安装所有 Python 依赖（包括 superlinked_rag）
install-superlinked: # Create a local Poetry virtual environment and install all required Python dependencies (with Superlinked enabled).
	poetry env use 3.11
	poetry install

# local-start-superlinked: 构建并启动专门用于 Superlinked 系列的本地 Docker 基础设施
local-start-superlinked: # Build and start local infrastructure used in the Superlinked series.
	docker compose -f docker-compose-superlinked.yml up --build -d

# local-stop-superlinked: 停止并移除用于 Superlinked 系列的 Docker 容器
local-stop-superlinked: # Stop local infrastructure used in the Superlinked series.
	docker compose -f docker-compose-superlinked.yml down --remove-orphans

# test-superlinked-server: 使用 Poetry 环境运行 Python 脚本，测试本地 Superlinked 服务是否正常
test-superlinked-server: # Ingest dummy data into the local superlinked server to check if it's working.
	poetry run python src/bonus_superlinked_rag/local_test.py

# local-bytewax-superlinked: 运行 Bytewax 流式处理流水线（Superlinked 版）
local-bytewax-superlinked: # Run the Bytewax streaming pipeline powered by Superlinked.
	RUST_BACKTRACE=full poetry run python -m bytewax.run src/bonus_superlinked_rag/main.py

# local-test-retriever-superlinked: 在 Docker 容器中执行 Python 模块，测试检索功能对接 Superlinked 服务
local-test-retriever-superlinked: # Call the retrieval module and query the Superlinked server & vector DB
	docker exec -it llm-twin-bytewax-superlinked python -m retriever
